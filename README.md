# GQH Hardware Track: Zero-Fabric Moving-Average Trade Signal

## Team Members

- Isaiah Diamond (email)

## Project Overview

A Tang Nano 20K design that receives 8-byte price packets over UART, keeps an independent 16-sample moving average for item A (0x11) and item B (0x22), detects price/average crossings, and returns BUY / SELL / repeat-last-action for each item in an 8-byte response.

The main idea: build the whole design out of the chip's flip-flops, carry-chain adder cells and distributed RAM instead of general LUT logic. The design uses **1 LUT** in the Gowin synthesis report.

## FPGA Implementation

Everything runs on the FPGA. No host software is used during judging.

- **UART receive:** a free-running counter makes a tick every 78 clocks (3 ticks per bit at 27 MHz). A start bit is detected on a tick, a one-hot chain times the frame, and data bits are read from fixed taps of a sample shift register (samples land within about ±1/6 bit of each bit center).
- **Packet assembly:** bytes shift into packet registers. Small rotating rings track the byte position.
- **Moving average:** one shared compute lane runs twice per packet, once after slot 1's price arrives and once after slot 2's. Per-item state (running sum, previous price, last action) lives in RAM addressed by item ID, so routing is by item ID only. The 16-price windows live in a RAM addressed by `index[3:0]`.
- **Math:** the sum update, floor averages (`>> 4`) and all comparisons use carry-chain ALU cells.
- **Crossing logic:** built from flip-flop set/reset/enable pins. Warm-up (index 0–15) and the index-0 reset are folded into the comparisons.
- **UART transmit:** the full response waveform (start, data, stop and 11 idle bit-times between bytes) is loaded into a 169-bit shift register and shifted out at 115200 baud.
- **Robustness:** a half-received packet is discarded after about 19 ms of silence, so a stray byte can't misalign the official run. The TX line is held idle for the first 19 ms after configuration.
- **Status LED:** `led0_n` lights while a byte is being received. `led1_n` is unused and driven high.

## Host-Side Tooling (Local Testing Only)

Not run during judging.

- `tests/21_quick_uart_test.py` and `tests/22_robust_uart_test.py`: organizer test scripts, unchanged except `PORT`.
- Pre-hardware simulation used Icarus Verilog / Verilator and Yosys. These are not part of the build.

## Hardware

- FPGA board: Tang Nano 20K
- FPGA number / asset tag assigned to team: `#___`
- Additional hardware/peripherals used: none

## HDL / Languages

- HDL used: Verilog-2001
- Host-side language(s) for local testing: Python 3 (pyserial)

## Toolchain

- Gowin EDA version: V1.9.11.03 Education (macOS)
- Device part number: GW2AR-LV18QN88C8/I7
- Other required software/tools: openFPGALoader (used locally to program over USB)
- Operating system: macOS

## Top-Level Entity / Module

```text
top
```

## Top-Level Ports

Port names match the organizer-supplied `19_tang_nano_20k.cst` exactly:

```text
sys_clk    pin 4   in   27 MHz clock
reset_btn  pin 87  in   pull-down (unused)
uart_rx_i  pin 70  in   BL616 -> FPGA
uart_tx_o  pin 69  out  FPGA -> BL616
led0_n     pin 15  out  active low, receive activity
led1_n     pin 16  out  active low, unused (driven high)
```

## Organizer-Supplied Constraint File

We use the organizer-provided `src/19_tang_nano_20k.cst`, unmodified, as the project's physical constraint file. No pins were assigned in FloorPlanner.

## Repository Structure

```text
quant_hacks.gprj           Gowin project
src/top.v                  HDL source (top module: top)
src/19_tang_nano_20k.cst   organizer constraint file
impl/                      Gowin synthesis and place & route outputs and reports
impl/pnr/quant_hacks.fs    programming file built from src/top.v
bitstream/quant_hacks.fs   copy of the final programming file (identical)
results/                   robust test summary and CSV from the final build
tests/                     organizer test scripts (set PORT, then run)
```

## Build Instructions

1. Open `quant_hacks.gprj` in Gowin EDA V1.9.11.03 Education.
2. Check that the project contains `src/top.v` and `src/19_tang_nano_20k.cst`.
3. Check Project → Configuration → Synthesize → General → Top Module/Entity is `top`.
4. Run Synthesis.
5. Run Place & Route (or Run All).
6. The programming file is written to `impl/pnr/quant_hacks.fs`.

## Programming the Tang Nano 20K

Gowin Programmer: Access Mode **SRAM Mode**, Operation **SRAM Program**, file `bitstream/quant_hacks.fs`.

Or with openFPGALoader (SRAM, volatile):

```text
openFPGALoader -b tangnano20k bitstream/quant_hacks.fs
```

- `.fs` file location in this repository: `bitstream/quant_hacks.fs` (same file as `impl/pnr/quant_hacks.fs`)

Wait about a second after programming before opening the COM port.

## Fixed UART Interface

The design follows the official interface:

```text
PC -> FPGA:
[index16][item1_8][price1_16][item2_8][price2_16]

FPGA -> PC:
[index16][item1_8][action1_8][item2_8][action2_8][reserved16]

reserved = 0x0000

ITEM_A = 0x11
ITEM_B = 0x22

NONE = 0x00
SELL = 0x01
BUY  = 0x02

UART = 115200 baud, 8N1, LSB first
Packet size = 8 bytes each direction
Multi-byte fields = big-endian
Routing = by item ID; response mirrors request slot order
```

## How to Reproduce the Demo

1. Program the board in SRAM mode with `bitstream/quant_hacks.fs` (Gowin Programmer, or `openFPGALoader -b tangnano20k bitstream/quant_hacks.fs`).
2. Wait about a second, then close Gowin Programmer and any serial terminals.
3. In `tests/21_quick_uart_test.py` and `tests/22_robust_uart_test.py`, set `PORT` to the board's serial port (for example `COM6` on Windows).
4. Run:

```text
pip install pyserial
python3 tests/21_quick_uart_test.py
python3 tests/22_robust_uart_test.py
```

Expected result:

```text
21_quick_uart_test.py  -> PASS
22_robust_uart_test.py -> Correct packets: 84
                          Correct individual actions: 168/168
                          Timeouts: 0
                          Estimated correctness points: 70.0 / 70
```

## Verification / Testing

- `21_quick_uart_test.py`: PASS.
- `22_robust_uart_test.py` (practice seed 0x57214720): 84/84 packets, 168/168 actions, 0 timeouts, 70.0/70. Repeated runs gave the same result.
- Before hardware, the design and its synthesized netlist were simulated against a Python model of the reference algorithm on several thousand packets, including real 115200 baud timing with our 0.16% clock offset.

## Judging Metrics / Results

> Official judging uses one 100-packet run (indices 0–99): 84 scored packets and 168 scored actions.

### Correctness

- Local test used: `22_robust_uart_test.py`
- Packet correctness (out of 84): 84
- Action correctness (out of 168): 168
- Estimated correctness points from `trade_summary_100.txt` (out of 70): 70.0

### Latency

- Average measured round-trip latency: 5.96 ms (macOS host)
- Idle time or buffering between response bytes (BL616 workaround): 11 idle bit-times (about 95 µs) between response bytes
- Test/setup used: `22_robust_uart_test.py`, MacBook Pro over the board's USB-C port

### LUT Usage

From **Synthesis Report → Resource → Resource Usage Summary**:

- **Total LUT (used for judging): 1**
- LUT2: 1
- LUT3: 0
- LUT4: 0
- Other relevant resource usage: 552 registers, 272 ALU, 18 SSRAM (RAM16), 0 BSRAM, 0 DSP. Place & Route: 291 logic cells (1 LUT, 290 ALU), timing met (Fmax about 191 MHz vs 27 MHz).

These resources are not scored, but we list them so the trade-off is clear: we used flip-flops, adder cells and distributed RAM in place of LUTs. Earlier conventional versions of this design used 374, 178 and 64 LUTs.

## External Libraries / IP / Starter Code

- Gowin primitives instantiated directly from the vendor library: `DFFR`, `DFFRE`, `DFFS`, `DFFSE`, `ALU`, `RAM16SDP4`.
- Organizer-provided `19_tang_nano_20k.cst` and test scripts.
- No IP cores or starter HDL. Developed with help from an AI assistant (Claude).

## Known Limitations

- Item routing uses bits 0 and 1 of the item byte, which assumes the fixed IDs 0x11 and 0x22.
- The UART stop bit is not checked.
- After configuration the TX line stays idle for about 19 ms. A partial packet is discarded after about 19 ms of silence.
- Receive sampling uses a fixed 3-ticks-per-bit grid, which relies on the BL616's accurate 115200 baud rate.
- The LUT count is low because logic was moved into flip-flop control pins and carry chains. Physical logic-cell usage is about 290 cells.

## Final Submission

- GitHub repository URL:
- Devpost project URL:

This repository must stay public through judging and must not be deleted or renamed.
