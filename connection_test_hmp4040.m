% Clear environment
clear; clc;

% Porta da usare (COM9)
port = "ASRL9::INSTR";
fprintf('Trying port: %s\n', port);

% Cleanup
clear psu;

% Connessione
psu = visadev(port);
psu.Timeout = 5;

fprintf('Connected to %s. Testing communication...\n', port);

% Test connessione
writeline(psu, "*IDN?");
idn = readline(psu);
fprintf('Device identification: %s\n', idn);

% Imposta il voltaggio a 3.3 V sul canale 1
voltage_set = 3.3;
cmd_voltage = sprintf("VOLT %.2f, CH1", voltage_set);
writeline(psu, cmd_voltage);
fprintf('Voltage set to %.2f V on channel 1.\n', voltage_set);

% Accende l'uscita del canale 1
writeline(psu, "OUTP ON, CH1");
fprintf('Output of channel 1 is now ON.\n');

% Attende 3 secondi prima di spegnere l'uscita
pause(3);

% (Opzionale) chiude il canale 1
writeline(psu, "OUTP OFF, CH1");

% Spegne tutte le uscite della power supply
writeline(psu, "OUTP:GEN OFF"); % oppure "OUTP OFF" a seconda del modello
fprintf('All outputs turned OFF.\n');
