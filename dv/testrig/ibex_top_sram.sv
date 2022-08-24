/**
 * Top level wrapper for Ibex that instantiates a disconnected RAM
 * (for some reason, not instantiating this RAM leads to undefined
 * references to memory functions)
 */

module ibex_top_sram import ibex_pkg::*; #(
  parameter bit          PMPEnable        = 1'b0,
  parameter int unsigned PMPGranularity   = 0,
  parameter int unsigned PMPNumRegions    = 4,
  parameter int unsigned MHPMCounterNum   = 0,
  parameter int unsigned MHPMCounterWidth = 40,
  parameter bit          RV32E            = 1'b0,
  parameter rv32m_e      RV32M            = RV32MFast,
  parameter rv32b_e      RV32B            = RV32BNone,
  parameter regfile_e    RegFile          = RegFileFF,
  parameter bit          BranchTargetALU  = 1'b0,
  parameter bit          WritebackStage   = 1'b0,
  parameter bit          ICache           = 1'b0,
  parameter bit          ICacheECC        = 1'b0,
  parameter bit          BranchPredictor  = 1'b0,
  parameter bit          DbgTriggerEn     = 1'b0,
  parameter int unsigned DbgHwBreakNum    = 1,
  parameter bit          SecureIbex       = 1'b0,
  parameter bit          ICacheScramble   = 1'b0,
  parameter lfsr_seed_t  RndCnstLfsrSeed  = RndCnstLfsrSeedDefault,
  parameter lfsr_perm_t  RndCnstLfsrPerm  = RndCnstLfsrPermDefault,
  parameter int unsigned DmHaltAddr       = 32'h1A110800,
  parameter int unsigned DmExceptionAddr  = 32'h1A110808,
  // Default seed and nonce for scrambling
  parameter logic [SCRAMBLE_KEY_W-1:0]   RndCnstIbexKey   = RndCnstIbexKeyDefault,
  parameter logic [SCRAMBLE_NONCE_W-1:0] RndCnstIbexNonce = RndCnstIbexNonceDefault
) (
  // Clock and Reset
  input  logic                         clk_i,
  input  logic                         rst_ni,

  input  logic                         test_en_i,     // enable all clock gates for testing
  input  prim_ram_1p_pkg::ram_1p_cfg_t ram_cfg_i,

  input  logic [31:0]                  hart_id_i,
  input  logic [31:0]                  boot_addr_i,

  // Instruction memory interface
  // Instructions will be provided by the simulation environment
  output logic                         instr_req_o,
  input  logic                         instr_gnt_i,
  input  logic                         instr_rvalid_i,
  output logic [31:0]                  instr_addr_o,
  input  logic [31:0]                  instr_rdata_i,
  input  logic [6:0]                   instr_rdata_intg_i,
  input  logic                         instr_err_i,

  // Interrupt inputs
  input  logic                         irq_software_i,
  input  logic                         irq_timer_i,
  input  logic                         irq_external_i,
  input  logic [14:0]                  irq_fast_i,
  input  logic                         irq_nm_i,       // non-maskeable interrupt

  // Scrambling Interface
  input  logic                         scramble_key_valid_i,
  input  logic [SCRAMBLE_KEY_W-1:0]    scramble_key_i,
  input  logic [SCRAMBLE_NONCE_W-1:0]  scramble_nonce_i,
  output logic                         scramble_req_o,

  // Debug Interface
  input  logic                         debug_req_i,
  output crash_dump_t                  crash_dump_o,
  output logic                         double_fault_seen_o,

  // RISC-V Formal Interface
  // Does not comply with the coding standards of _i/_o suffixes, but follows
  // the convention of RISC-V Formal Interface Specification.
`ifdef RVFI
  output logic                         rvfi_valid,
  output logic [63:0]                  rvfi_order,
  output logic [31:0]                  rvfi_insn,
  output logic                         rvfi_trap,
  output logic                         rvfi_halt,
  output logic                         rvfi_intr,
  output logic [ 1:0]                  rvfi_mode,
  output logic [ 1:0]                  rvfi_ixl,
  output logic [ 4:0]                  rvfi_rs1_addr,
  output logic [ 4:0]                  rvfi_rs2_addr,
  output logic [ 4:0]                  rvfi_rs3_addr,
  output logic [31:0]                  rvfi_rs1_rdata,
  output logic [31:0]                  rvfi_rs2_rdata,
  output logic [31:0]                  rvfi_rs3_rdata,
  output logic [ 4:0]                  rvfi_rd_addr,
  output logic [31:0]                  rvfi_rd_wdata,
  output logic [31:0]                  rvfi_pc_rdata,
  output logic [31:0]                  rvfi_pc_wdata,
  output logic [31:0]                  rvfi_mem_addr,
  output logic [ 3:0]                  rvfi_mem_rmask,
  output logic [ 3:0]                  rvfi_mem_wmask,
  output logic [31:0]                  rvfi_mem_rdata,
  output logic [31:0]                  rvfi_mem_wdata,
  output logic [31:0]                  rvfi_ext_mip,
  output logic                         rvfi_ext_nmi,
  output logic                         rvfi_ext_debug_req,
  output logic [63:0]                  rvfi_ext_mcycle,
`endif

  // CPU Control Signals
  input  fetch_enable_t                fetch_enable_i,
  output logic                         alert_minor_o,
  output logic                         alert_major_internal_o,
  output logic                         alert_major_bus_o,
  output logic                         core_sleep_o,

  // DFT bypass controls
  input logic                          scan_rst_ni
);

  // Core data memory interface
  logic                         core_req        [1];
  logic                         core_gnt        [1];
  logic                         core_rvalid     [1];
  logic                         core_we         [1];
  logic [3:0]                   core_be         [1];
  logic [31:0]                  core_addr       [1];
  logic [31:0]                  core_wdata      [1];
  logic [6:0]                   core_wdata_intg [1];
  logic [31:0]                  core_rdata      [1];
  logic [6:0]                   core_rdata_intg [1];
  logic                         core_err        [1];

  // RAM data memory interface
  logic                         ram_req        [1];
  logic                         ram_gnt        [1];
  logic                         ram_rvalid     [1];
  logic                         ram_we         [1];
  logic [3:0]                   ram_be         [1];
  logic [31:0]                  ram_addr       [1];
  logic [31:0]                  ram_wdata      [1];
  logic [6:0]                   ram_wdata_intg [1];
  logic [31:0]                  ram_rdata      [1];
  logic [6:0]                   ram_rdata_intg [1];
  logic                         ram_err        [1];

  // Memory configuration
  logic [31:0] addr_base [1];
  logic [31:0] addr_mask [1];
  assign addr_base[0] = 32'h8000_0000;
  assign addr_mask[0] = 32'h007F_FFFF;

  // whether the memory access is in bounds
  logic access_err_d, access_err_q;

  logic core_err_or, ram_we_and;

  assign access_err_d = core_req[0]
                        && (core_addr[0] < addr_base[0]
                            || core_addr[0] > addr_base[0] + addr_mask[0]);

  // keep track of last cycle's request so we can use it for error setting
  logic [31:0] core_addr_q;
  always @(posedge clk_i) begin
    access_err_q <= access_err_d;
  end
  // if the core requests memory out of range, set error
  assign core_err_or = core_err[0] || access_err_q;
  assign ram_we_and = ram_we[0] && !access_err_d;

  bus #(
    .NrDevices    ( 1),
    .NrHosts      ( 1),
    .DataWidth    (32),
    .AddressWidth (32)
  ) u_bus (
    .clk_i (clk_i),
    .rst_ni (rst_ni),

    .host_req_i    (core_req   ),
    .host_gnt_o    (core_gnt   ),
    .host_addr_i   (core_addr  ),
    .host_we_i     (core_we    ),
    .host_be_i     (core_be    ),
    .host_wdata_i  (core_wdata ),
    .host_rvalid_o (core_rvalid),
    .host_rdata_o  (core_rdata ),
    .host_err_o    (core_err   ),

    .device_req_o    (ram_req   ),
    .device_addr_o   (ram_addr  ),
    .device_we_o     (ram_we    ),
    .device_be_o     (ram_be    ),
    .device_wdata_o  (ram_wdata ),
    .device_rvalid_i (ram_rvalid),
    .device_rdata_i  (ram_rdata ),
    .device_err_i    (ram_err   ),

    .cfg_device_addr_base (addr_base),
    .cfg_device_addr_mask (addr_mask)
  );

  // ibex toplevel instantiation
  ibex_top #(
    .PMPEnable        ( PMPEnable        ),
    .PMPGranularity   ( PMPGranularity   ),
    .PMPNumRegions    ( PMPNumRegions    ),
    .MHPMCounterNum   ( MHPMCounterNum   ),
    .MHPMCounterWidth ( MHPMCounterWidth ),
    .RV32E            ( RV32E            ),
    .RV32M            ( RV32M            ),
    .RV32B            ( RV32B            ),
    .RegFile          ( RegFile          ),
    .BranchTargetALU  ( BranchTargetALU  ),
    .ICache           ( ICache           ),
    .ICacheECC        ( ICacheECC        ),
    .BranchPredictor  ( BranchPredictor  ),
    .DbgTriggerEn     ( DbgTriggerEn     ),
    .DbgHwBreakNum    ( DbgHwBreakNum    ),
    .WritebackStage   ( WritebackStage   ),
    .SecureIbex       ( SecureIbex       ),
    .ICacheScramble   ( ICacheScramble   ),
    .RndCnstLfsrSeed  ( RndCnstLfsrSeed  ),
    .RndCnstLfsrPerm  ( RndCnstLfsrPerm  ),
    .DmHaltAddr       ( DmHaltAddr       ),
    .DmExceptionAddr  ( DmExceptionAddr  )
  ) u_ibex_top (
    .clk_i,
    .rst_ni,

    .test_en_i,
    .scan_rst_ni,
    .ram_cfg_i,

    .hart_id_i,
    .boot_addr_i,

    .instr_req_o,
    .instr_gnt_i,
    .instr_rvalid_i,
    .instr_addr_o,
    .instr_rdata_i,
    .instr_rdata_intg_i,
    .instr_err_i,

    // This is connected to the bus
    .data_req_o        (core_req[0]       ),
    .data_gnt_i        (core_gnt[0]       ),
    .data_rvalid_i     (core_rvalid[0]    ),
    .data_we_o         (core_we[0]        ),
    .data_be_o         (core_be[0]        ),
    .data_addr_o       (core_addr[0]      ),
    .data_wdata_o      (core_wdata[0]     ),
    .data_wdata_intg_o (core_wdata_intg[0]),
    .data_rdata_i      (core_rdata[0]     ),
    .data_rdata_intg_i (core_rdata_intg[0]),
    .data_err_i        (core_err_or       ),

    .irq_software_i,
    .irq_timer_i,
    .irq_external_i,
    .irq_fast_i,
    .irq_nm_i,

    .scramble_key_valid_i,
    .scramble_key_i,
    .scramble_nonce_i,
    .scramble_req_o,

    .debug_req_i,
    .crash_dump_o,
    .double_fault_seen_o,

`ifdef RVFI
    .rvfi_valid,
    .rvfi_order,
    .rvfi_insn,
    .rvfi_trap,
    .rvfi_halt,
    .rvfi_intr,
    .rvfi_mode,
    .rvfi_ixl,
    .rvfi_rs1_addr,
    .rvfi_rs2_addr,
    .rvfi_rs3_addr,
    .rvfi_rs1_rdata,
    .rvfi_rs2_rdata,
    .rvfi_rs3_rdata,
    .rvfi_rd_addr,
    .rvfi_rd_wdata,
    .rvfi_pc_rdata,
    .rvfi_pc_wdata,
    .rvfi_mem_addr,
    .rvfi_mem_rmask,
    .rvfi_mem_wmask,
    .rvfi_mem_rdata,
    .rvfi_mem_wdata,
    .rvfi_ext_mip,
    .rvfi_ext_nmi,
    .rvfi_ext_debug_req,
    .rvfi_ext_mcycle,
`endif

    .fetch_enable_i,
    .alert_minor_o,
    .alert_major_internal_o,
    .alert_major_bus_o,
    .core_sleep_o
  );


  // SRAM block for instruction and data storage
  // TODO this ram exists solely to allow compilation.
  ram_1p #(
      .Depth((64*1024)/4), // 64KiB memory, Depth is number of 32b words
      .MemInitFile("") // Memory should be zeroed to start with
    ) u_ram (
      .clk_i       (clk_i),
      .rst_ni      (rst_ni),

      .req_i     (ram_req[0]   ),
      .we_i      (ram_we_and   ),
      .be_i      (ram_be[0]    ),
      .addr_i    (ram_addr[0]  ),
      .wdata_i   (ram_wdata[0] ),
      .rvalid_o  (ram_rvalid[0]),
      .rdata_o   (ram_rdata[0] )
    );

endmodule
