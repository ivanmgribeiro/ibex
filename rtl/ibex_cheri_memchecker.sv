module ibex_cheri_memchecker #(
    parameter bit DataMem = 1'b1,
    parameter bit StableOut = 1'b1,
    parameter int unsigned CheriCapWidth = 91
) (
    input logic clk_i,
    input logic rst_ni,

    // this provides the authority for memory access
    input logic [CheriCapWidth-1:0] auth_cap_i,

    // data access information
    input logic        data_req_i,
    input logic        data_gnt_i,
    input logic        data_rvalid_i,
    input logic [31:0] data_addr_i,
    input logic        data_we_i,
    input logic [1:0]  data_type_i,
    input logic [3:0]  data_be_i,
    input logic        data_cap_i,

    // new output signal to prevent CHERI-disallowed writes from writing memory
    output logic       data_we_o,
    // exceptions that have been caused
    output logic [ibex_pkg::CheriExcWidth-1:0] cheri_mem_exc_o,
    // whether there was a length exception caused by fetching the second half
    // of an instruction
    output logic                               instr_upper_exc_o
);
  import ibex_pkg::*;

  // CHERI module inputs & outputs
  logic [31:0] auth_cap_getAddr_o;
  logic        auth_cap_isValidCap_o;
  logic        auth_cap_isSealed_o;
  logic [31:0] auth_cap_getBase_o;
  logic [32:0] auth_cap_getTop_o;
  logic [30:0] auth_cap_getPerms_o;

  logic [CheriExcWidth-1:0] cheri_mem_exc_q, cheri_mem_exc_d;
  logic                     instr_upper_exc_q, instr_upper_exc_d;

  // get data size from type to use in bounds checking, and then zero-extend
  // it to the correct size (33 bits since capability "top" is 33 bits)
  logic [3:0]  data_size;
  logic [32:0] data_size_ext;
  if (DataMem) begin
    assign data_size = data_type_i == 2'b00 ? 4'h4 : // Word
                       data_type_i == 2'b01 ? 4'h2 : // Halfword
                       data_type_i == 2'b10 ? 4'h1 : // Byte
                                              4'h8;  // Double
  end else begin
    assign data_size = 4'h2; // instruction accesses are 2 bytes
  end
  assign data_size_ext = {29'h0, data_size};

  logic cap_first_access;

  // calculate actual data start address using byte enable
  // upper bits are identical since Ibex only produces accesses aligned to 4 bytes
  logic [31:0] data_addr_actual, data_addr_actual_upper;;
  assign data_addr_actual[31:2]       = data_addr_i[31:2];
  assign data_addr_actual_upper[31:2] = data_addr_i[31:2];
  if (DataMem) begin
    // for data memory, check byte enables to get the real address
    assign data_addr_actual[1:0]  = data_be_i[0] == 1'b1 ? 2'b00
                                  : data_be_i[1] == 1'b1 ? 2'b01
                                  : data_be_i[2] == 1'b1 ? 2'b10
                                  : 2'b11;
    assign data_addr_actual_upper[1:0] = 2'bX;
  end else begin
    // for instructions, bottom bit is always 0 and need to check 2 accesses
    // (in case we read a compressed instruction)
    assign data_addr_actual[1:0]       = 2'b00;
    assign data_addr_actual_upper[1:0] = 2'b10;
  end

  // perform the memory checks
  assign cheri_mem_exc_d[           TAG_VIOLATION] = ~auth_cap_isValidCap_o;
  assign cheri_mem_exc_d[          SEAL_VIOLATION] =  auth_cap_isSealed_o;
  assign cheri_mem_exc_d[   PERMIT_LOAD_VIOLATION] = ~data_we_i & ~auth_cap_getPerms_o[2];
  assign cheri_mem_exc_d[  PERMIT_STORE_VIOLATION] =  data_we_i & ~auth_cap_getPerms_o[3];
  assign cheri_mem_exc_d[PERMIT_EXECUTE_VIOLATION] =  DataMem & ~auth_cap_getPerms_o[PermitExecuteIndex];
  assign cheri_mem_exc_d[        LENGTH_VIOLATION] = (data_addr_actual < auth_cap_getBase_o)
                                                     | ({1'b0, data_addr_actual} + data_size_ext > auth_cap_getTop_o);
  // don't bother checking if it is below base (if it is, then there will be
  // a length violation in the lower word anyway
  assign instr_upper_exc_d                         = DataMem ? 0 : {1'b0, data_addr_actual_upper} > auth_cap_getTop_o;

  // only generate exceptions when requests are made
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (~rst_ni) begin
      cheri_mem_exc_q   <= '0;
      instr_upper_exc_q <= '0;
    end else if (data_req_i & data_gnt_i) begin
      cheri_mem_exc_q   <= cheri_mem_exc_d;
      instr_upper_exc_q <= instr_upper_exc_d;
    end
  end

  assign cheri_mem_exc_o   = StableOut | data_rvalid_i ? cheri_mem_exc_q   : 0;
  assign instr_upper_exc_o = StableOut | data_rvalid_i ? instr_upper_exc_q : 0;

  assign data_we_o = data_we_i & ~|cheri_mem_exc_d;

  // CHERI module instantiation
  module_wrap64_isValidCap auth_cap_isValidCap (
    .wrap64_isValidCap_cap(auth_cap_i),
    .wrap64_isValidCap    (auth_cap_isValidCap_o)
  );

  logic [6:0] auth_cap_getKind_o;
  module_wrap64_getKind auth_cap_getKind(
    .wrap64_getKind_cap(auth_cap_i),
    .wrap64_getKind    (auth_cap_getKind_o)
  );
  assign auth_cap_isSealed_o = auth_cap_getKind_o[6:4] != 3'b000;

  module_wrap64_getBase auth_cap_getBase(
    .wrap64_getBase_cap(auth_cap_i),
    .wrap64_getBase    (auth_cap_getBase_o)
  );

  module_wrap64_getTop auth_cap_getTop(
    .wrap64_getTop_cap(auth_cap_i),
    .wrap64_getTop    (auth_cap_getTop_o)
  );

  module_wrap64_getPerms auth_cap_getPerms(
    .wrap64_getPerms_cap(auth_cap_i),
    .wrap64_getPerms    (auth_cap_getPerms_o)
  );

endmodule