AXI4-Lite UVM Verification Environment

A complete UVM-based verification environment for an AXI4-Lite slave with
256-byte internal memory. The testbench includes a reusable agent,
reference-model scoreboard, functional coverage with covergroups, and
concurrent SVA protocol assertions.

## Overview

This project verifies an AXI4-Lite slave that supports:
- Full-word and byte-strobe writes (WSTRB)
- Read-back with OKAY response
- DECERR response for out-of-range addresses (addr >= 256)
- 256 bytes of word-addressable memory

The verification environment is built entirely in SystemVerilog + UVM 1.2
and runs on any UVM-capable simulator (Aldec Riviera Pro, Questa, VCS, Xcelium).

## Architecture
+------------------- axi4lite_env -------------------+
| |
axi4lite_sequence(s) --> sequencer --> driver --> [ AXI4-Lite IF ] --> DUT
| |
| monitor <---------------------+
| | (analysis port)
| +------------+------------+
| v v
| scoreboard (ref model) coverage (covergroups)
+----------------------------------------------------+

text

**Data flow:** `sequence → sequencer → driver → DUT → monitor → scoreboard + coverage`

## File Structure
axi4lite-uvm-verification/
├── rtl/
│ └── axi4lite_slave.sv # DUT: AXI4-Lite slave, 256×32-bit memory
├── tb/
│ └── axi4lite_pkg.sv # Interface, UVM classes, tb_top
├── sim/
│ └── run.f # Run file (EDA Playground / Questa)
├── scripts/
│ └── run_regression.py # Python regression automation
├── docs/
│ └── coverage_report.txt # Coverage report
└── README.md

text

## UVM Components

| Component | Role |
|-----------|------|
| `axi4lite_seq_item` | Transaction with rand fields + constraints |
| `axi4lite_sanity_seq` | Directed write/read pairs (smoke test) |
| `axi4lite_random_seq` | Constrained-random transactions |
| `axi4lite_error_seq` | Out-of-range (DECERR) accesses |
| `axi4lite_driver` | Drives AXI4-Lite handshakes from transactions |
| `axi4lite_monitor` | Reconstructs completed transactions, analysis port |
| `axi4lite_scoreboard` | Reference-model memory, checks every read |
| `axi4lite_coverage` | Covergroup: op, address range, strobe, op×addr cross |
| `axi4lite_agent` | Driver + monitor + sequencer bundle |
| `axi4lite_env` | Agent + scoreboard + coverage wiring |
| `axi4lite_sanity_test` | Smoke test (10 directed write/read pairs) |
| `axi4lite_regression_test` | Full regression (default) |

## How to Run

### Option A: EDA Playground (free, no install)

1. Login at [edaplayground.com](https://edaplayground.com)
2. Left pane: **Tools & Simulators → Aldec Riviera Pro**
3. Tick **UVM 1.2**
4. Tick **Open EPWave after run** (for waveforms)
5. Paste `rtl/axi4lite_slave.sv` → **Design** box
6. Paste `tb/axi4lite_pkg.sv` → **Testbench** box
7. Run with plusarg `+UVM_TESTNAME=axi4lite_regression_test`

### Option B: Local simulator

```bash
cd sim
make questa TEST=axi4lite_regression_test    # ModelSim/Questa
# or
make vcs    TEST=axi4lite_regression_test    # Synopsys VCS
# or
make xrun   TEST=axi4lite_regression_test    # Cadence Xcelium
Tests
Test	Description
axi4lite_sanity_test	10 directed write/read pairs (smoke test)
axi4lite_regression_test	Directed corners + 16 write/read pairs + 40 random + 10 error transactions (default)
Expected Results
text
UVM_INFO ... [SCB] ============ SCOREBOARD SUMMARY ============
UVM_INFO ... [SCB] writes=66 reads=66 MATCH=66 MISMATCH=0
UVM_INFO ... [SCB] RESULT: PASS
UVM_INFO ... [COV] Functional coverage = 100.00%
UVM_INFO ... [TEST_DONE] UVM_ERROR : 0  UVM_FATAL : 0
Functional Coverage
Coverpoint	Bins	Status
cp_op	read, write	100%
cp_addr	low, mid, high	100%
cp_strb	full, single, other	100%
cp_resp	okay, decerr	100%
cross op×addr	all combinations	100%
Total functional coverage: 100.00%

SVA Assertions
Concurrent assertions bound to the interface:

Assertion	Checks
A_AWVALID_STABLE	AWVALID stable until AWREADY
A_WVALID_STABLE	WVALID stable until WREADY
A_ARVALID_STABLE	ARVALID stable until ARREADY
A_BRESP_LEGAL	BRESP only OKAY (2'b00) or DECERR (2'b11)
A_RRESP_LEGAL	RRESP only OKAY (2'b00) or DECERR (2'b11)
Error-Path Verification (DECERR)
The environment verifies the decode-error path:

Slave returns DECERR (2'b11) for any out-of-range access (addr >= 256)

Memory is left untouched on DECERR

axi4lite_error_seq drives directed + randomized out-of-range accesses

Scoreboard predicts response from address (in-range → OKAY, out-of-range → DECERR)

Coverage adds decerr response bin and oob address bin

Bug Injection & Debug Story
The DUT has a deliberate, toggleable bug to prove the environment catches
real RTL defects.

Bug 1: WSTRB ignored (+define+INJECT_WSTRB_BUG)
Bug: Write path ignores WSTRB, writes full 32-bit word every time

Expected: Partial-strobe write (WSTRB=0x1) updates only byte 0

Caught by: Reference-model scoreboard honors strobes

Result: UVM_ERROR ... READ MISMATCH addr=0x20 expected=0xFFFFFFAA got=0x000000AA

Bug 2: Illegal response (+define+INJECT_BRESP_ERR)
Bug: Slave returns SLVERR (2'b10) on normal access

Caught by: Bound SVA assertions A_BRESP_LEGAL / A_RRESP_LEGAL fire immediately

Result: "[SVA] BRESP not OKAY"

Debug loop: reproduce → localize from scoreboard diff → form hypothesis → confirm.

Regression Automation
scripts/run_regression.py runs the regression across multiple seeds:

bash
python scripts/run_regression.py
Output:

text
Running seed=1...
  PASS  coverage=100.00%
Running seed=7...
  PASS  coverage=100.00%
...
=== REGRESSION SUMMARY ===
PASS = 5
FAIL = 0
Avg coverage = 100.00%
Skills Demonstrated
Full UVM component hierarchy and phasing

Constrained-random stimulus with constraint blocks and randomize()

Reference-model scoreboard (self-checking, not just log-watching)

Functional coverage with covergroup / coverpoint / cross

Assertion-based verification (concurrent SVA) for protocol legality

Reusable agent and layered sequence library

Python regression automation

Debug methodology: reproduce → localize → hypothesize → confirm

Notes
Tested against UVM 1.2 semantics

Runs on Aldec Riviera Pro (EDA Playground), Questa, VCS, Xcelium

Two injectable bugs included to demonstrate scoreboard + SVA layers
each catching defects
