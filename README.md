# Test Runner

MATLAB script for automated angular scans of a motor under different magnetic field conditions,
synchronizing torque measurements (DigiVision), current acquisition (PSU), and angular positioning (Zaber stage).

## Requirements

### Software
- MATLAB with [Instrument Control Toolbox](https://www.mathworks.com/products/instrument.html)
- [Zaber Motion Library for MATLAB](https://software.zaber.com/motion-library/docs/tutorials/install/matlab)
- [DigiVision](https://www.burster.com/en/sensor-signal-processing/software/digivision)

### Hardware
- Zaber rotary stage (connected via COM port)
- Programmable Power Supply Unit (VISA interface)
- Torque measurement system compatible with DigiVision

## Setup

1. Start DigiVision and open **Measurement mode**
2. Set the magnetic field manually
3. Edit the `CONFIG` section at the top of the script
4. Run the script and press **Enter** when prompted
