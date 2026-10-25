//============================================================================
//
//  chip_pool_pkg — bus types for a multi-board core's shared CPU / sound chip pool (canonical; same file in every core)
//  Copyright (C) 2026 Rodimus
//
//  Only one board runs at a time, so the CPUs and sound chips are instanced once in rtl/konami82_board.sv
//  and the active board drives them through these buses (selected by variant). *_i = board to chip,
//  *_o = chip to every board. Reset is the core reset.
//
//============================================================================

package chip_pool_pkg;

// Z80 (T80s, Mode 0, T2Write 1, IOWait 1; WAIT_n / BUSRQ_n inactive)
typedef struct packed {
    logic        ce;
    logic        int_n;
    logic        nmi_n;
    logic  [7:0] di;
} z80_i_t;

typedef struct packed {
    logic [15:0] a;
    logic  [7:0] dout;
    logic        m1_n;
    logic        mreq_n;
    logic        iorq_n;
    logic        rd_n;
    logic        wr_n;
    logic        rfsh_n;
} z80_o_t;

// MC6809E (mc6809is; HALT / DMABREQ inactive)
typedef struct packed {
    logic        fall_e;
    logic        fall_q;
    logic        irq_n;
    logic        firq_n;
    logic        nmi_n;
    logic  [7:0] d;
} m6809_i_t;

typedef struct packed {
    logic [15:0] a;
    logic  [7:0] dout;
    logic        rw;
    logic        lic;
} m6809_o_t;

// Z80 (T80s, as z80_i_t) with RESET_n on the bus: Konami82's board watchdogs reset the main and sound CPUs
typedef struct packed {
    logic        reset_n;
    logic        ce;
    logic        int_n;
    logic        nmi_n;
    logic  [7:0] di;
} z80r_i_t;

typedef struct packed {
    logic [15:0] a;
    logic  [7:0] dout;
    logic        m1_n;
    logic        mreq_n;
    logic        iorq_n;
    logic        rd_n;
    logic        wr_n;
    logic        rfsh_n;
} z80r_o_t;

// MC6809E (mc6809is, as m6809_i_t) with RESET on the bus: Konami82's board watchdogs
typedef struct packed {
    logic        reset_n;
    logic        fall_e;
    logic        fall_q;
    logic        irq_n;
    logic        firq_n;
    logic        nmi_n;
    logic  [7:0] d;
} m6809r_i_t;

typedef struct packed {
    logic [15:0] a;
    logic  [7:0] dout;
    logic        rw;
    logic        lic;
} m6809r_o_t;

// AY-3-8910 (jt49_bus, sel = 1)
typedef struct packed {
    logic        ce;
    logic        bdir;
    logic        bc1;
    logic  [7:0] din;
    logic  [7:0] ioa_in;
    logic  [7:0] iob_in;
} ay_i_t;

typedef struct packed {
    logic  [7:0] dout;
    logic  [7:0] a;
    logic  [7:0] b;
    logic  [7:0] c;
    logic  [7:0] iob_out;
    logic  [9:0] sound;                 // jt49 internal A+B+C mix (registered per accumulator cycle)
} ay_o_t;

// 8039 (T48 t8039_notri_extrom, EA low, program on pmem; T0 / T1 low, P1 / P2 inputs high)
typedef struct packed {
    logic        xtal_en;
    logic        int_n;
    logic  [7:0] db;
    logic  [7:0] pmem_d;
} mcs48_i_t;

typedef struct packed {
    logic  [7:0] p1;
    logic  [7:0] p2;
    logic [11:0] pmem_a;
    logic        rd_n;
} mcs48_o_t;

// Z80 (T80pa, Mode 0; BUSRQ_n inactive). RESET_n is on the bus: Lady Bug / 8203 hold their CPUs in reset ~48 ms past the core reset
typedef struct packed {
    logic        reset_n;
    logic        cen_p;
    logic        cen_n;
    logic        wait_n;
    logic        int_n;
    logic        nmi_n;
    logic  [7:0] di;
} z80pa_i_t;

typedef struct packed {
    logic [15:0] a;
    logic  [7:0] dout;
    logic        m1_n;
    logic        mreq_n;
    logic        iorq_n;
    logic        rd_n;
    logic        wr_n;
    logic        rfsh_n;
} z80pa_o_t;

// SN76489 (jt89, INTERPOL16 0, MODE 0). rst is on the bus: Lady Bug resets its pair on power-on only
typedef struct packed {
    logic        rst;
    logic        ce;
    logic        wr_n;
    logic        cs_n;
    logic  [7:0] din;
} sn76489_i_t;

typedef struct packed {
    logic [10:0] sound;                 // signed
    logic        ready;
} sn76489_o_t;

// MB88 (mb88 / mb88_core; STBY / SC inputs inactive, RAM clear = core reset)
typedef struct packed {
    logic        ena;
    logic        reset_n;
    logic  [3:0] k;
    logic [15:0] r_in;          // {R3, R2, R1, R0}
    logic        irq_n;
    logic        tc_n;
    logic        si_n;
    logic  [7:0] rom_d;
} mb88_i_t;

typedef struct packed {
    logic [15:0] r_out;         // {R3, R2, R1, R0}
    logic  [7:0] o;             // {OH, OL}
    logic        o_wr;
    logic  [3:0] p;
    logic [10:0] rom_a;
} mb88_o_t;

// NEW-Namco6809-2026-10-24: types added by the Namco6809 core (merge into the master copy) -------------------

// Namco 15XX WSG (8 voices). The registers live in the first 64 bytes of the CPU-shared sound RAM; the chip
// snoops CPU writes there (MAME namco_15xx_device::sharedram_w). dac_mode picks the board's volume DAC
// (0 = Super Pac-Man LS273 + 4066 resistor ladder, 1 = Mappy / Gaplus 99XX).
typedef struct packed {
    logic        sound_en;      // LS259 SOUND ON
    logic  [1:0] dac_mode;
    logic        reg_wr;        // one clock per CPU write to shared RAM offset 0x00-0x3F
    logic  [5:0] reg_addr;
    logic  [7:0] reg_din;
    logic  [3:0] wave_d;        // waveform PROM nibble at wave_a
} wsg15_i_t;

typedef struct packed {
    logic  [7:0] wave_a;        // waveform PROM address {waveform, step}
    logic [15:0] sound;         // signed mono
} wsg15_o_t;

// Namco 56XX / 58XX / 59XX custom I/O (MB8843, undumped: behavioural per MAME namcoio.cpp), runtime-configured
// by kind; CPU side is the 16XX nibble buffer (16 nibbles per chip).
typedef struct packed {
    logic  [1:0] kind;          // 0 = 56XX, 1 = 58XX, 2 = 59XX
    logic        reset_n;       // LS259 4 RESET
    logic        run;           // vblank strobe: process the command (MAME customio_run 50 us after vblank)
    logic        wr;
    logic  [3:0] addr;
    logic  [3:0] din;
    logic [15:0] in;            // {in3, in2, in1, in0} 4-bit input ports
} namcoio_i_t;

typedef struct packed {
    logic  [3:0] dout;
    logic  [7:0] out;           // {out1, out0} 4-bit output ports (lamps, coin lockout, DIP mux select)
} namcoio_o_t;

endpackage
