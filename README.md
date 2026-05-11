# Test_runner

This repository contains a MATLAB script for automated angular scans of a motor under different magnetic field conditions, synchronizing torque measurements (DigiVision) with current acquisition (PSU) and angular positioning (Zaber stage).

## Requirements

### Software

- MATLAB (with Instrument Control Toolbox)
- Zaber Motion Library for MATLAB  
[  https://www.zaber.com/software/docs/motion-library/matlab/
](https://software.zaber.com/motion-library/docs/tutorials/install/matlab)
- DigiVision software  
[  https://www.burster.com/en/sensor-signal-processing/software/digivision
](https://www.burster.com/products/sensors/torque-sensors)
### MATLAB requirements
- Instrument Control Toolbox
- Java enabled (for keyboard automation via `Robot` class)

---

## Hardware

- Zaber rotary stage (connected via COM port)
- Programmable Power Supply Unit (VISA interface)
- Torque measurement system compatible with DigiVision

---

## DigiVision Setup

Before running the script:

- Start DigiVision manually
- Open **Measurement mode**
