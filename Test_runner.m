%% =========================================================================
%  Maxon RE6 - Magnetic Field Test - Automated Acquisition Script
%
%  Measures torque (DigiVision, F5 trigger) and current (PSU polling)
%  as a function of the Zaber goniometer angle.
%
%  INSTRUCTIONS:
%    1. Set the magnetic field MANUALLY before starting.
%    2. Configure the parameters in the CONFIG section below.
%    3. Run the script. Do not touch the PC during acquisition.
%
%  OUTPUT:
%    - Current CSV: current_M{ID}_{field}mT_{cond}_rep{N}_TIMESTAMP.csv
%      (only if MODE = 'ON')
%    - Torque files: saved automatically by DigiVision
% =========================================================================
clc; clear; close all;

%% =========================================================================
%  CONFIG — edit before each run
%% =========================================================================
MOTOR_ID        = 1;          % Motor ID: 1, 2, or 3
FIELD_MT        = 0;          % Magnetic field set [mT]: 0, 50, 100, 150, 200
MODE            = 'ON';       % Condition: 'ON' or 'OFF'
REP             = 1;          % Repetition number: 1, 2, or 3

COM_PORT        = 'COM8';     % Zaber serial port
VISA_PORT       = 'ASRL9::INSTR'; % PSU VISA address (change the number after ASRL to match COM port)

VOLTAGE_SET     = 4.5;        % Nominal motor voltage [V]
STEP_DEG        = 10;         % Angular step [deg]
N_STEPS         = 2;          % Number of steps (36 x 10° = 360°)
OFFSET_DEG      = 45;         % Mechanical stage offset (real 0° = 45° Zaber)

MEAS_DURATION   = 15;         % Acquisition duration per position [s]
N_SAMPLES_MAX   = 2000;       % Buffer size for pre-allocation (generous value)

SETTLE_TIME     = 5;          % Wait time after movement [s]
HOME_WAIT       = 3;          % Wait time after homing [s]

OUTPUT_DIR      = 'Data';     % Current CSV output folder
%% =========================================================================

% Input validation
assert(ismember(MOTOR_ID, [1 2 3]),            'MOTOR_ID must be 1, 2 or 3');
assert(ismember(FIELD_MT, [0 50 100 150 200]), 'FIELD_MT is not valid');
assert(ismember(MODE, {'ON','OFF'}),            'MODE must be ON or OFF');
assert(ismember(REP, [1 2 3]),                  'REP must be 1, 2 or 3');

% Output filename
timestamp  = datestr(now, 'yyyymmdd_HHMMSS');
csv_name   = sprintf('current_M%d_%dmT_%s_rep%d_%s.csv', ...
                     MOTOR_ID, FIELD_MT, MODE, REP, timestamp);
if ~exist(OUTPUT_DIR, 'dir'), mkdir(OUTPUT_DIR); end
csv_path   = fullfile(OUTPUT_DIR, csv_name);

% Run summary
fprintf('\n========================================\n');
fprintf('  MAXON TEST — RUN SUMMARY\n');
fprintf('  Motor ID  : %d\n', MOTOR_ID);
fprintf('  Field     : %d mT\n', FIELD_MT);
fprintf('  Condition : Motor %s\n', MODE);
fprintf('  Rep       : %d\n', REP);
fprintf('  Output    : %s\n', csv_path);
fprintf('========================================\n');
input('  Press ENTER to start...', 's');

%% =========================================================================
%  INITIALIZATION
%% =========================================================================
import zaber.motion.ascii.*;
import zaber.motion.*;
import java.awt.Robot;
import java.awt.event.KeyEvent;

robot = Robot();

% Bring DigiVision to foreground
result = system('powershell -Command "$wshell = New-Object -ComObject wscript.shell; [System.Environment]::Exit(-$wshell.AppActivate(''Measurement mode''))"');
pause(0.5);

if result == 0
    error('DigiVision not found! Start DigiVision before running the script.');
end

%% =========================================================================
%  CONNECTIONS
%% =========================================================================
try
    %% Zaber
    fprintf('Connecting to Zaber on %s...\n', COM_PORT);
    conn    = Connection.openSerialPort(COM_PORT);
    devices = conn.detectDevices();
    if isempty(devices)
        error('No Zaber device found on %s.', COM_PORT);
    end
    device = devices(1);
    ax     = device.getAxis(1);
    fprintf('Zaber connected.\n');

    %% PSU
    fprintf('Connecting to PSU on %s...\n', VISA_PORT);
    psu         = visadev(VISA_PORT);
    psu.Timeout = 5;
    fprintf('PSU connected.\n');

    % Set voltage (always, even in OFF mode, for safety)
    writeline(psu, sprintf('VOLT %.2f, CH1', VOLTAGE_SET));

    if strcmp(MODE, 'ON')
        writeline(psu, 'OUTP ON, CH1');
        fprintf('Motor ON at %.2f V.\n', VOLTAGE_SET);
    else
        writeline(psu, 'OUTP OFF, CH1');
        fprintf('Motor OFF.\n');
    end

    %% =====================================================================
    %  HOMING AND INITIAL POSITIONING
    %% =====================================================================
    fprintf('Homing goniometer...\n');
    device.getAllAxes().home();
    pause(HOME_WAIT);
    fprintf('Homing complete.\n');

    fprintf('Moving to initial position (%.1f deg Zaber = 0 deg real)...\n', OFFSET_DEG);
    ax.moveAbsolute(OFFSET_DEG, Units.ANGLE_DEGREES, true); % true = wait for move to complete
    pause(SETTLE_TIME);

    %% =====================================================================
    %  DATA PRE-ALLOCATION
    %% =====================================================================
    n_positions  = N_STEPS + 1;              % 0°, 10°, ..., 360°
    angles_real  = zeros(1, n_positions);
    timestamps_v = strings(1, n_positions);
    n_samples_actual = zeros(1, n_positions); % actual samples per position

    if strcmp(MODE, 'ON')
        current_matrix = NaN(N_SAMPLES_MAX, n_positions);
    end

    %% =====================================================================
    %  ACQUISITION LOOP
    %% =====================================================================
    for i = 1:n_positions

        % Current real position
        pos_zaber = ax.getPosition(Units.ANGLE_DEGREES);
        pos_real  = pos_zaber - OFFSET_DEG;
        angles_real(i)  = pos_real;
        timestamps_v(i) = string(datestr(now, 'HH:MM:SS'));

        fprintf('\n[%d/%d] Angle: %.1f deg — %s\n', i, n_positions, pos_real, timestamps_v(i));

        % --- DigiVision trigger ---
        system('powershell -Command "$wshell = New-Object -ComObject wscript.shell; $wshell.AppActivate(''Measurement mode'')"');
        pause(0.3);
        robot.keyPress(KeyEvent.VK_F5);
        robot.keyRelease(KeyEvent.VK_F5);
        fprintf('  DigiVision trigger sent (F5).\n');

        % --- Current acquisition (Motor ON only) ---
        if strcmp(MODE, 'ON')
            fprintf('  Acquiring current for %.1f s (time-based)...\n', MEAS_DURATION);
            k       = 0;
            samples = NaN(N_SAMPLES_MAX, 1);   % pre-allocated buffer
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
                    warning('Sample %d invalid: "%s"', k, raw);
                end
                % No pause() — VISA round-trip is the natural rate-limiter
            end
            elapsed = toc(t_acq);
            k = min(k, N_SAMPLES_MAX);          % buffer overflow safety
            n_samples_actual(i) = k;
            current_matrix(1:k, i) = samples(1:k);
            fprintf('  Current acquired: %d samples in %.1f s (%.0f Hz effective).\n', ...
                    k, elapsed, k/elapsed);
        else
            % Motor OFF: wait for DigiVision acquisition duration anyway
            fprintf('  Waiting for DigiVision acquisition (%d s)...\n', MEAS_DURATION);
            pause(MEAS_DURATION);
        end

        % --- Move to next angle (if not last step) ---
        if i < n_positions
            fprintf('  Moving +%.1f deg...\n', STEP_DEG);
            ax.moveRelative(STEP_DEG, Units.ANGLE_DEGREES, true); % true = wait for move to complete
            pause(SETTLE_TIME);
        end
    end

    %% =====================================================================
    %  END OF ACQUISITION — TURN OFF PSU, RETURN TO HOME
    %% =====================================================================
    fprintf('\nAcquisition complete. Turning off PSU...\n');
    writeline(psu, 'OUTP OFF, CH1');
    writeline(psu, 'OUTP:GEN OFF');

    fprintf('Returning to initial position...\n');
    ax.moveAbsolute(OFFSET_DEG, Units.ANGLE_DEGREES, true);
    pause(2);
    ax.stop();
    conn.close();
    fprintf('Zaber disconnected.\n');

    %% =====================================================================
    %  SAVE CURRENT CSV (Motor ON only)
    %% =====================================================================
    if strcmp(MODE, 'ON')
        % Trim matrix to the maximum number of samples actually acquired
        max_k = max(n_samples_actual);
        current_matrix = current_matrix(1:max_k, :);

        col_names = strcat("Angle_", string(round(angles_real)), "_deg");
        T = array2table(current_matrix, 'VariableNames', col_names);

        % Write metadata as header rows in the file
        if ~exist(OUTPUT_DIR, 'dir'), mkdir(OUTPUT_DIR); end
        fid = fopen(csv_path, 'w');
        if fid == -1
            error('Cannot open file for writing: %s', csv_path);
        end
        fprintf(fid, '# Motor_ID,%d\n', MOTOR_ID);
        fprintf(fid, '# Field_mT,%d\n', FIELD_MT);
        fprintf(fid, '# Condition,%s\n', MODE);
        fprintf(fid, '# Rep,%d\n', REP);
        fprintf(fid, '# Voltage_V,%.2f\n', VOLTAGE_SET);
        fprintf(fid, '# Timestamp,%s\n', timestamp);
        fprintf(fid, '# N_samples_per_position (actual, may vary),%s\n', ...
                num2str(n_samples_actual));
        fprintf(fid, '%s\n', strjoin(col_names, ','));
        fclose(fid);

        writetable(T, csv_path, 'WriteMode', 'append', 'WriteVariableNames', false);
        fprintf('Current CSV saved: %s\n', csv_path);
    end

    %% =====================================================================
    %  FINAL SUMMARY
    %% =====================================================================
    fprintf('\n========================================\n');
    fprintf('  RUN COMPLETE\n');
    fprintf('  Motor %d | %d mT | %s | Rep %d\n', MOTOR_ID, FIELD_MT, MODE, REP);
    fprintf('  Positions acquired: %d\n', n_positions);
    if strcmp(MODE, 'ON')
        mean_curr = mean(current_matrix, 'all', 'omitnan');
        fprintf('  Mean current: %.4f A\n', mean_curr);
        fprintf('  Samples per position: min=%d, max=%d\n', ...
                min(n_samples_actual), max(n_samples_actual));
        fprintf('  File: %s\n', csv_path);
    end
    fprintf('========================================\n');

catch exception
    fprintf('\n!!! ERROR: %s\n', exception.message);
    disp(getReport(exception));

    % Emergency cleanup
    fprintf('Attempting emergency cleanup...\n');
    try
        conn.close();
        fprintf('Zaber connection closed.\n');
    catch; end
    try
        writeline(psu, 'OUTP OFF, CH1');
        writeline(psu, 'OUTP:GEN OFF');
        fprintf('PSU turned off.\n');
    catch; end
    try
        ax.moveAbsolute(OFFSET_DEG, Units.ANGLE_DEGREES, true);
        conn.close();
        fprintf('Zaber returned to home and disconnected.\n');
    catch; end
end
