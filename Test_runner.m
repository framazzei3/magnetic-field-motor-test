%% =========================================================================
%  Maxon RE6 - Magnetic Field Test - Automated Acquisition Script
%  
%  Misura coppia (DigiVision, trigger F5) e corrente (PSU polling)
%  in funzione dell'angolo del goniometro Zaber.
%
%  ISTRUZIONI:
%    1. Impostare il campo magnetico MANUALMENTE prima di avviare.
%    2. Configurare i parametri nella sezione CONFIG qui sotto.
%    3. Avviare lo script. Non toccare il PC durante l'acquisizione.
%
%  OUTPUT:
%    - CSV corrente: current_M{ID}_{field}mT_{cond}_rep{N}_TIMESTAMP.csv
%      (solo se MODE = 'ON')
%    - File coppia: salvati automaticamente da DigiVision
% =========================================================================
clc; clear; close all;

%% =========================================================================
%  CONFIG — modificare prima di ogni run
%% =========================================================================
MOTOR_ID        = 1;          % ID motore: 1, 2, o 3
FIELD_MT        = 0;          % Campo magnetico impostato [mT]: 0,50,100,150,200
MODE            = 'ON';      % Condizione: 'ON' oppure 'OFF'
REP             = 1;          % Numero ripetizione: 1, 2, o 3

COM_PORT        = 'COM8';     % Porta seriale Zaber
VISA_PORT       = 'ASRL9::INSTR'; % Indirizzo VISA PSU (cambiare il numero dopo ASRL in base all COM)

VOLTAGE_SET     = 4.5;        % Tensione nominale motore [V]
STEP_DEG        = 10;         % Passo angolare [deg]
N_STEPS         = 2;         % Numero passi (36 x 10° = 360°)
OFFSET_DEG      = 45;         % Offset meccanico stage (0° reale = 45° Zaber)

MEAS_DURATION   = 15;         % Durata acquisizione per posizione [s]
N_SAMPLES_MAX   = 2000;       % Dimensione buffer pre-allocazione (valore generoso)

SETTLE_TIME     = 5;          % Tempo attesa dopo movimento [s]
HOME_WAIT       = 3;          % Tempo attesa dopo homing [s]

OUTPUT_DIR      = 'Data';     % Cartella output CSV corrente
%% =========================================================================

% Validazione input
assert(ismember(MOTOR_ID, [1 2 3]),         'MOTOR_ID deve essere 1, 2 o 3');
assert(ismember(FIELD_MT, [0 50 100 150 200]), 'FIELD_MT non valido');
assert(ismember(MODE, {'ON','OFF'}),         'MODE deve essere ON o OFF');
assert(ismember(REP, [1 2 3]),               'REP deve essere 1, 2 o 3');

% Nome file output
timestamp  = datestr(now, 'yyyymmdd_HHMMSS');
csv_name   = sprintf('current_M%d_%dmT_%s_rep%d_%s.csv', ...
                     MOTOR_ID, FIELD_MT, MODE, REP, timestamp);
if ~exist(OUTPUT_DIR, 'dir'), mkdir(OUTPUT_DIR); end
csv_path   = fullfile(OUTPUT_DIR, csv_name);

% Riepilogo run
fprintf('\n========================================\n');
fprintf('  MAXON TEST — RUN SUMMARY\n');
fprintf('  Motor ID  : %d\n', MOTOR_ID);
fprintf('  Field     : %d mT\n', FIELD_MT);
fprintf('  Condition : Motor %s\n', MODE);
fprintf('  Rep       : %d\n', REP);
fprintf('  Output    : %s\n', csv_path);
fprintf('========================================\n');
input('  Premi INVIO per avviare...', 's');

%% =========================================================================
%  INIZIALIZZAZIONE
%% =========================================================================
import zaber.motion.ascii.*;
import zaber.motion.*;
import java.awt.Robot;
import java.awt.event.KeyEvent;

robot = Robot();

% Porta in primo piano DigiVision
result = system('powershell -Command "$wshell = New-Object -ComObject wscript.shell; [System.Environment]::Exit(-$wshell.AppActivate(''Measurement mode''))"');
pause(0.5);

if result == 0
    error('DigiVision non trovato! Avvia DigiVision prima di eseguire lo script.');
end

%% =========================================================================
%  CONNESSIONI
%% =========================================================================
try
    %% Zaber
    fprintf('Connessione Zaber su %s...\n', COM_PORT);
    conn    = Connection.openSerialPort(COM_PORT);
    devices = conn.detectDevices();
    if isempty(devices)
        error('Nessun dispositivo Zaber trovato su %s.', COM_PORT);
    end
    device = devices(1);
    ax     = device.getAxis(1);
    fprintf('Zaber connesso.\n');

    %% PSU
    fprintf('Connessione PSU su %s...\n', VISA_PORT);
    psu         = visadev(VISA_PORT);
    psu.Timeout = 5;
    fprintf('PSU connessa.\n');

    % Configura tensione (sempre, anche in OFF, per sicurezza)
    writeline(psu, sprintf('VOLT %.2f, CH1', VOLTAGE_SET));

    if strcmp(MODE, 'ON')
        writeline(psu, 'OUTP ON, CH1');
        fprintf('Motore ON a %.2f V.\n', VOLTAGE_SET);
    else
        writeline(psu, 'OUTP OFF, CH1');
        fprintf('Motore OFF.\n');
    end

    %% =====================================================================
    %  HOMING E POSIZIONAMENTO INIZIALE
    %% =====================================================================
    fprintf('Homing goniometro...\n');
    device.getAllAxes().home();
    pause(HOME_WAIT);
    fprintf('Homing completato.\n');

    fprintf('Movimento a posizione iniziale (%.1f deg Zaber = 0 deg reali)...\n', OFFSET_DEG);
    ax.moveAbsolute(OFFSET_DEG, Units.ANGLE_DEGREES, true); % true = attendi fine movimento
    pause(SETTLE_TIME);

    %% =====================================================================
    %  PRE-ALLOCAZIONE DATI
    %% =====================================================================
    n_positions  = N_STEPS + 1;              % 0°, 10°, ..., 360°
    angles_real  = zeros(1, n_positions);
    timestamps_v = strings(1, n_positions);
    n_samples_actual = zeros(1, n_positions); % campioni reali per ogni posizione

    if strcmp(MODE, 'ON')
        current_matrix = NaN(N_SAMPLES_MAX, n_positions);
    end

    %% =====================================================================
    %  LOOP DI ACQUISIZIONE
    %% =====================================================================
    for i = 1:n_positions

        % Posizione reale attuale
        pos_zaber = ax.getPosition(Units.ANGLE_DEGREES);
        pos_real  = pos_zaber - OFFSET_DEG;
        angles_real(i)  = pos_real;
        timestamps_v(i) = string(datestr(now, 'HH:MM:SS'));

        fprintf('\n[%d/%d] Angolo: %.1f deg — %s\n', i, n_positions, pos_real, timestamps_v(i));

        % --- Trigger DigiVision ---
        system('powershell -Command "$wshell = New-Object -ComObject wscript.shell; $wshell.AppActivate(''Measurement mode'')"');
        pause(0.3);
        robot.keyPress(KeyEvent.VK_F5);
        robot.keyRelease(KeyEvent.VK_F5);
        fprintf('  DigiVision trigger inviato (F5).\n');

        % --- Acquisizione corrente (solo Motor ON) ---
        if strcmp(MODE, 'ON')
            fprintf('  Acquisizione corrente per %.1f s (time-based)...\n', MEAS_DURATION);
            k       = 0;
            samples = NaN(N_SAMPLES_MAX, 1);   % buffer pre-allocato
            t_acq   = tic;
            while toc(t_acq) < MEAS_DURATION
                writeline(psu, 'MEAS:CURR? CH1');
                raw = readline(psu);
                val = str2double(raw);
                k   = k + 1;
                if k <= N_SAMPLES_MAX
                    samples(k) = val;
                end
                if isnan(val)
                    warning('Campione %d non valido: "%s"', k, raw);
                end
                % Nessun pause() — il round-trip VISA è il rate-limiter naturale
            end
            elapsed = toc(t_acq);
            k = min(k, N_SAMPLES_MAX);          % sicurezza overflow buffer
            n_samples_actual(i) = k;
            current_matrix(1:k, i) = samples(1:k);
            fprintf('  Corrente acquisita: %d campioni in %.1f s (%.0f Hz effettivi).\n', ...
                    k, elapsed, k/elapsed);
        else
            % Motor OFF: aspetta comunque la durata di acquisizione DigiVision
            fprintf('  Attesa acquisizione DigiVision (%d s)...\n', MEAS_DURATION);
            pause(MEAS_DURATION);
        end

        % --- Movimento al prossimo angolo (se non ultimo) ---
        if i < n_positions
            fprintf('  Movimento +%.1f deg...\n', STEP_DEG);
            ax.moveRelative(STEP_DEG, Units.ANGLE_DEGREES, true); % true = attendi fine
            pause(SETTLE_TIME);
        end
    end

    %% =====================================================================
    %  FINE ACQUISIZIONE — SPEGNI PSU, TORNA A HOME
    %% =====================================================================
    fprintf('\nAcquisizione completata. Spegnimento PSU...\n');
    writeline(psu, 'OUTP OFF, CH1');
    writeline(psu, 'OUTP:GEN OFF');

    fprintf('Ritorno alla posizione iniziale...\n');
    ax.moveAbsolute(OFFSET_DEG, Units.ANGLE_DEGREES, true);
    pause(2);
    ax.stop();
    conn.close();
    fprintf('Zaber disconnesso.\n');

    %% =====================================================================
    %  SALVATAGGIO CSV CORRENTE (solo Motor ON)
    %% =====================================================================
    if strcmp(MODE, 'ON')
        % Tronca la matrice al massimo numero di campioni reali acquisiti
        max_k = max(n_samples_actual);
        current_matrix = current_matrix(1:max_k, :);

        col_names = strcat("Angle_", string(round(angles_real)), "_deg");
        T = array2table(current_matrix, 'VariableNames', col_names);

        % Aggiungi metadati come righe header nel file
        if ~exist(OUTPUT_DIR, 'dir'), mkdir(OUTPUT_DIR); end
        fid = fopen(csv_path, 'w');
        if fid == -1
            error('Impossibile aprire il file per la scrittura: %s', csv_path);
        end
        fprintf(fid, '# Motor_ID,%d\n', MOTOR_ID);
        fprintf(fid, '# Field_mT,%d\n', FIELD_MT);
        fprintf(fid, '# Condition,%s\n', MODE);
        fprintf(fid, '# Rep,%d\n', REP);
        fprintf(fid, '# Voltage_V,%.2f\n', VOLTAGE_SET);
        fprintf(fid, '# Timestamp,%s\n', timestamp);
        fprintf(fid, '# N_samples_per_position (actual, may vary),%s\n', ...
                num2str(n_samples_actual));
        fprintf(fid, '%s\n', strjoin(col_names, ','));  % <-- RIGA AGGIUNTA
        fclose(fid);
        
        writetable(T, csv_path, 'WriteMode', 'append', 'WriteVariableNames', false);
        fprintf('CSV corrente salvato: %s\n', csv_path);
    end

    %% =====================================================================
    %  RIEPILOGO FINALE
    %% =====================================================================
    fprintf('\n========================================\n');
    fprintf('  RUN COMPLETATO\n');
    fprintf('  Motor %d | %d mT | %s | Rep %d\n', MOTOR_ID, FIELD_MT, MODE, REP);
    fprintf('  Posizioni acquisite: %d\n', n_positions);
    if strcmp(MODE, 'ON')
        mean_curr = mean(current_matrix, 'all', 'omitnan');
        fprintf('  Corrente media: %.4f A\n', mean_curr);
        fprintf('  Campioni per posizione: min=%d, max=%d\n', ...
                min(n_samples_actual), max(n_samples_actual));
        fprintf('  File: %s\n', csv_path);
    end
    fprintf('========================================\n');

catch exception
    fprintf('\n!!! ERRORE: %s\n', exception.message);
    disp(getReport(exception));

    % Cleanup di emergenza
    fprintf('Tentativo cleanup di emergenza...\n');
    try
        conn.close();
        fprintf('Connessione Zaber chiusa.\n');
    catch; end
    try
        writeline(psu, 'OUTP OFF, CH1');
        writeline(psu, 'OUTP:GEN OFF');
        fprintf('PSU spenta.\n');
    catch; end
    try
        ax.moveAbsolute(OFFSET_DEG, Units.ANGLE_DEGREES, true);
        conn.close();
        fprintf('Zaber portato a home e disconnesso.\n');
    catch; end
end