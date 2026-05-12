% Clear environment
clear; clc;

% Port to use (COM9)
port = "ASRL9::INSTR";
fprintf('Trying port: %s\n', port);

% Cleanup
clear psu;

% Connection
psu = visadev(port);
psu.Timeout = 5;
fprintf('Connected to %s. Testing communication...\n', port);

% Connection test
writeline(psu, "*IDN?");
idn = readline(psu);
fprintf('Device identification: %s\n', idn);

% Set voltage to 3.3 V on channel 1
voltage_set = 3.3;
cmd_voltage = sprintf("VOLT %.2f, CH1", voltage_set);
writeline(psu, cmd_voltage);
fprintf('Voltage set to %.2f V on channel 1.\n', voltage_set);

% Turn on channel 1 output
writeline(psu, "OUTP ON, CH1");
fprintf('Output of channel 1 is now ON.\n');

% Wait 3 seconds before turning off the output
pause(3);

% (Optional) turn off channel 1
writeline(psu, "OUTP OFF, CH1");

% Turn off all power supply outputs
writeline(psu, "OUTP:GEN OFF"); % or "OUTP OFF" depending on the model
fprintf('All outputs turned OFF.\n');
