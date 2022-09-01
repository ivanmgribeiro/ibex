module ibex_cheri_alu #(
  parameter int unsigned CheriCapWidth = 91,
  parameter int unsigned IntWidth = 32
) (
  input ibex_pkg::cheri_base_opcode_e             base_opcode_i,
  input ibex_pkg::cheri_threeop_funct7_e          threeop_opcode_i,
  input ibex_pkg::cheri_s_a_d_funct5_e  s_a_d_opcode_i,

  input logic [CheriCapWidth-1:0] operand_a_i,
  input logic [CheriCapWidth-1:0] operand_b_i,

  output logic [IntWidth-1:0] alu_operand_a_o,
  output logic [IntWidth-1:0] alu_operand_b_o,
  output ibex_pkg::alu_op_e alu_operator_o,

  input logic [32:0] alu_result_i,

  output logic [CheriCapWidth-1:0] result_o,
  output logic wrote_capability,

  output logic [ibex_pkg::CheriExcWidth-1:0] exceptions_a_o,
  output logic [ibex_pkg::CheriExcWidth-1:0] exceptions_b_o

);
  import ibex_pkg::*;

  // Verbosity: 0 = no printing; 1 = print each instruction.
  localparam bit Verbosity = 1'b0;

  // Constant parameters
  // TODO perhaps these should be moved to ibex_pkg?
  //    (or perhaps ibex_cheri_pkg?)
  localparam int unsigned ExceptionWidth  = 22;
  localparam int unsigned KindWidth      = 7;
  localparam int unsigned OTypeWidth      = 4;
  localparam int unsigned RegsPerQuarter  = 4;
  localparam int unsigned FlagWidth       = 1;
  localparam int unsigned PermsWidth      = 31;
  localparam int unsigned LengthWidth     = 33;
  localparam int unsigned OffsetWidth     = 32;
  localparam int unsigned BaseWidth       = 32;
  localparam int unsigned ImmWidth        = 12;

  // there are 22 exceptions currently defined in the CHERI-RISCV spec
  // TODO see if there are any unused exceptions (there are some that are MIPS-only)
  logic [CheriExcWidth-1:0] exceptions_a;
  logic [CheriExcWidth-1:0] exceptions_b;

  // Operands a and b as integers (ie bottom IntWidth bits)
  logic [IntWidth-1:0] operand_a_int = operand_a_i[IntWidth-1:0];
  logic [IntWidth-1:0] operand_b_int = operand_b_i[IntWidth-1:0];


  // function input and output declarations
  // these are inputs and outputs for modules that are generated from bluespec code
  // see https://github.com/CTSRD-CHERI/cheri-cap-lib for the bluespec code
  // This is being used because the spec for cheri capability compression is still being worked on
  // so it is possible the internals of the functions might change
  // naming: O_FFF...FFF_D
  // where O is the operand being worked on (operand a or b)
  //       F is the function being used
  //       D is the direction of the connection - _i means it is an input to the function
  //                                              _o means it is an output from the function
  logic [IntWidth-1:0]    a_setBounds_i;
  logic [CheriCapWidth:0] a_setBounds_o;

  logic [IntWidth-1:0] a_getAddr_o;

  logic [IntWidth-1:0] b_getAddr_o;

  logic [IntWidth:0] a_getTop_o;

  logic [IntWidth:0] b_getTop_o;

  logic [CheriCapWidth-1:0] a_setKind_cap_i;
  logic [    KindWidth-1:0] a_setKind_i;
  logic [    KindWidth-1:0] a_setKind_int;
  logic [CheriCapWidth-1:0] a_setKind_o;

  logic [    KindWidth-1:0] b_setKind_i;
  logic [CheriCapWidth-1:0] b_setKind_o;

  logic [PermsWidth-1:0] a_getPerms_o;

  logic [PermsWidth-1:0] b_getPerms_o;

  logic [   PermsWidth-1:0] a_setPerms_i;
  logic [CheriCapWidth-1:0] a_setPerms_o;

  logic [   PermsWidth-1:0] b_setPerms_i;
  logic [CheriCapWidth-1:0] b_setPerms_o;

  logic                     a_setFlags_i;
  logic [CheriCapWidth-1:0] a_setFlags_o;

  logic [   IntWidth-1:0] a_setOffset_i;
  logic [CheriCapWidth:0] a_setOffset_o;

  logic [IntWidth-1:0] a_getBase_o;

  logic [IntWidth-1:0] b_getBase_o;

  logic [IntWidth-1:0] a_getOffset_o;

  logic [IntWidth-1:0] b_getOffset_o;

  logic a_isValidCap_o;

  logic b_isValidCap_o;

  logic [KindWidth-1:0] a_getKind_o;
  logic [KindWidth-1:0] b_getKind_o;

  // the lower bits of the Kind hold the object type
  // TODO interacting with the "Kind" and "Type" of a capability needs nasty
  // code atm. Should discuss with cheri-cap-lib what would be a cleaner way
  // to do this
  logic [OTypeWidth-1:0] a_getOType_o = a_getKind_o[OTypeWidth-1:0];
  logic [OTypeWidth-1:0] b_getOType_o = b_getKind_o[OTypeWidth-1:0];

  logic a_isSealed_o = a_getKind_o[KindWidth-1:OTypeWidth] != 0;
  logic b_isSealed_o = b_getKind_o[KindWidth-1:OTypeWidth] != 0;

  logic a_isSentry_o = a_getKind_o[KindWidth-1:OTypeWidth] == 1;
  logic b_isSentry_o = b_getKind_o[KindWidth-1:OTypeWidth] == 1;

  logic a_isReserved_o = a_getKind_o[KindWidth-1:OTypeWidth] == 2
                       | a_getKind_o[KindWidth-1:OTypeWidth] == 3;
  logic b_isReserved_o = b_getKind_o[KindWidth-1:OTypeWidth] == 2
                       | b_getKind_o[KindWidth-1:OTypeWidth] == 3;

  logic a_isSealedWithType_o = a_getKind_o[KindWidth-1:OTypeWidth] == 4;
  logic b_isSealedWithType_o = b_getKind_o[KindWidth-1:OTypeWidth] == 4;

  logic [IntWidth:0] a_getLength_o;

  logic a_getFlags_o;

  logic                     a_setValidCap_i;
  logic [CheriCapWidth-1:0] a_setValidCap_o;

  logic                     b_setValidCap_i;
  logic [CheriCapWidth-1:0] b_setValidCap_o;

  logic [   IntWidth-1:0] a_setAddr_i;
  logic [CheriCapWidth:0] a_setAddr_o;

  logic [   IntWidth-1:0] b_setAddr_i;
  logic [CheriCapWidth:0] b_setAddr_o;

  logic a_isInBounds_isTopIncluded_i;
  logic a_isInBounds_o;

  logic b_isInBounds_isTopIncluded_i;
  logic b_isInBounds_o;

  //////////////////////////
  // CHERI ALU operations //
  //////////////////////////

  always_comb begin
    exceptions_a_o = '0;
    exceptions_b_o = '0;

    alu_operand_a_o  = '0;
    alu_operand_b_o  = '0;
    alu_operator_o   = ALU_ADD;
    result_o         = '0;
    wrote_capability = '0;

    a_setBounds_i   = '0;
    a_setKind_cap_i = '0;
    a_setKind_i     = '0;
    b_setKind_i     = '0;
    a_setPerms_i    = '0;
    b_setPerms_i    = '0;
    a_setFlags_i    = '0;
    a_setOffset_i   = '0;
    a_setValidCap_i = '0;
    b_setValidCap_i = '0;
    a_setAddr_i     = '0;
    b_setAddr_i     = '0;
    a_isInBounds_isTopIncluded_i = '0;
    b_isInBounds_isTopIncluded_i = '0;

    case (base_opcode_i)
      THREE_OP: begin
        case (threeop_opcode_i)
          C_SPECIAL_RW: begin
            // operand b is the register id
            // operand a is the data that is (maybe) going to be written to the register
            // this operation is implemented in other places since there's nothing the ALU can do
            // for it
            result_o = operand_a_i;
            wrote_capability = 1'b1;

            if (Verbosity) begin
              $display("cspecialrw output: %h", result_o);
            end
          end

          C_SET_BOUNDS: begin
            a_setBounds_i = operand_b_int;
            result_o = a_setBounds_o[CheriCapWidth-1:0];
            wrote_capability = 1'b1;

            alu_operand_a_o = a_getAddr_o;
            alu_operand_b_o = operand_b_int;
            alu_operator_o = ALU_ADD;

            exceptions_a_o[   TAG_VIOLATION] = exceptions_a[  TAG_VIOLATION];
            exceptions_a_o[  SEAL_VIOLATION] = exceptions_a[ SEAL_VIOLATION];
            exceptions_a_o[LENGTH_VIOLATION] = exceptions_a[LENGTH_VIOLATION]
                                             | alu_result_i > a_getTop_o;

            if (Verbosity) begin
              $display("csetbounds output: %h   exceptions: %h", result_o, exceptions_a_o);
            end
          end

          C_SET_BOUNDS_EXACT: begin
            a_setBounds_i = operand_b_int;
            result_o = a_setBounds_o[CheriCapWidth-1:0];
            wrote_capability = 1'b1;

            alu_operand_a_o = a_getAddr_o;
            alu_operand_b_o = operand_b_int;
            alu_operator_o = ALU_ADD;

            exceptions_a_o[           TAG_VIOLATION] = exceptions_a[           TAG_VIOLATION];
            exceptions_a_o[          SEAL_VIOLATION] = exceptions_a[          SEAL_VIOLATION];
            exceptions_a_o[        LENGTH_VIOLATION] = exceptions_a[        LENGTH_VIOLATION]
                                                     | alu_result_i > a_getTop_o;
            exceptions_a_o[INEXACT_BOUNDS_VIOLATION] = ~a_setBounds_o[CheriCapWidth];

            if (Verbosity) begin
              $display("csetboundse output: %h   exceptions: %h   exceptions_b: %h", result_o, exceptions_a_o, exceptions_b_o);
            end
          end

          C_SEAL: begin
            a_setKind_cap_i = operand_a_i;
            // TODO this will need to be changed
            a_setKind_i = b_getAddr_o[KindWidth-1:0];
            result_o = a_setKind_o;
            wrote_capability = 1'b1;

            exceptions_a_o[ TAG_VIOLATION] = exceptions_a[ TAG_VIOLATION];
            exceptions_a_o[SEAL_VIOLATION] = exceptions_a[SEAL_VIOLATION];

            exceptions_b_o[        TAG_VIOLATION] = exceptions_b[        TAG_VIOLATION];
            exceptions_b_o[       SEAL_VIOLATION] = exceptions_b[       SEAL_VIOLATION];
            exceptions_b_o[     LENGTH_VIOLATION] = exceptions_b[     LENGTH_VIOLATION]
                                                  | ({1'b0, b_getAddr_o} >= b_getTop_o)
                                                  | (b_getAddr_o > CheriMaxOType);
            exceptions_b_o[PERMIT_SEAL_VIOLATION] = exceptions_b[PERMIT_SEAL_VIOLATION];

            if (Verbosity) begin
              $display("cseal output: %h   exceptions: %h   exceptions_b: %h", result_o, exceptions_a_o, exceptions_b_o);
            end
          end

          C_UNSEAL: begin
            a_setPerms_i = a_getPerms_o;
            a_setPerms_i[PermitGlobalIndex] = a_getPerms_o[PermitGlobalIndex] & b_getPerms_o[PermitGlobalIndex];
            a_setKind_cap_i = a_setPerms_o;
            a_setKind_i = {KindWidth{1'b1}};
            result_o = a_setKind_o;
            wrote_capability = 1'b1;

            exceptions_a_o[ TAG_VIOLATION] = exceptions_a[TAG_VIOLATION];
            exceptions_a_o[SEAL_VIOLATION] = !a_isSealed_o;

            exceptions_b_o[          TAG_VIOLATION] = exceptions_b[TAG_VIOLATION];
            exceptions_b_o[         SEAL_VIOLATION] = b_isSealed_o;
            exceptions_b_o[         TYPE_VIOLATION] = b_getAddr_o != {{(IntWidth-OTypeWidth){1'b0}}, a_getOType_o};
            exceptions_b_o[PERMIT_UNSEAL_VIOLATION] = exceptions_b[PERMIT_UNSEAL_VIOLATION];
            exceptions_b_o[       LENGTH_VIOLATION] = {1'b0, b_getAddr_o} >= b_getTop_o;

            if (Verbosity) begin
              $display("cunseal output: %h   exceptions: %h   exceptions_b: %h", result_o, exceptions_a_o, exceptions_b_o);
            end
          end

          C_AND_PERM: begin
            a_setPerms_i = a_getPerms_o & operand_b_i[PermsWidth-1:0];
            result_o = a_setPerms_o;
            wrote_capability = 1'b1;

            exceptions_a_o[ TAG_VIOLATION] = exceptions_a[ TAG_VIOLATION];
            exceptions_a_o[SEAL_VIOLATION] = exceptions_a[SEAL_VIOLATION];

            if (Verbosity) begin
              $display("candperm output: %h   exceptions: %h   exceptions_b: %h", result_o, exceptions_a_o, exceptions_b_o);
            end
          end

          C_SET_FLAGS: begin
            a_setFlags_i = operand_b_i[FlagWidth-1:0];
            result_o = a_setFlags_o;
            wrote_capability = 1'b1;

            exceptions_a_o[SEAL_VIOLATION] = exceptions_a[SEAL_VIOLATION];

            if (Verbosity) begin
              $display("csetflags output: %h   exceptions: %h   exceptions_b: %h", result_o, exceptions_a_o, exceptions_b_o);
            end
          end

          C_SET_OFFSET: begin
            a_setOffset_i = operand_b_int;

            result_o = a_setOffset_o[CheriCapWidth-1:0];
            wrote_capability = 1'b1;

            exceptions_a_o[SEAL_VIOLATION] = exceptions_a[SEAL_VIOLATION];

            if (Verbosity) begin
              $display("csetoffset output: %h   exceptions: %h   exceptions_b: %h", result_o, exceptions_a_o, exceptions_b_o);
            end
          end

          C_SET_ADDR: begin
            a_setAddr_i = operand_b_i[IntWidth-1:0];
            result_o = a_setAddr_o[CheriCapWidth-1:0];

            wrote_capability = 1'b1;

            exceptions_a_o[SEAL_VIOLATION] = exceptions_a[SEAL_VIOLATION];

            if (Verbosity) begin
              $display("csetaddr output: %h   exceptions: %h   exceptions_b: %h", result_o, exceptions_a_o, exceptions_b_o);
            end
          end

          C_INC_OFFSET: begin
            // TODO remove adders here?
            a_setOffset_i = a_getOffset_o + operand_b_int;
            result_o = a_setOffset_o[CheriCapWidth-1:0];
            // only preserve the tag if the result was "exact"
            result_o[CheriCapWidth-1] = result_o[CheriCapWidth-1] & a_setOffset_o[CheriCapWidth];

            wrote_capability = 1'b1;

            exceptions_a_o[SEAL_VIOLATION] = exceptions_a[SEAL_VIOLATION];

            if (Verbosity) begin
              $display("cincoffset output: %h   exceptions: %h   exceptions_b: %h", result_o, exceptions_a_o, exceptions_b_o);
            end
          end

          C_TO_PTR: begin
            result_o[IntWidth-1:0] = a_isValidCap_o ? a_getAddr_o - b_getBase_o : IntWidth'(1'b0);

            wrote_capability = 1'b0;

            exceptions_a_o[SEAL_VIOLATION] = exceptions_a[SEAL_VIOLATION];

            exceptions_b_o[ TAG_VIOLATION] = exceptions_b[ TAG_VIOLATION];

            if (Verbosity) begin
              $display("ctoptr output: %h   exceptions: %h   exceptions_b: %h", result_o, exceptions_a_o, exceptions_b_o);
            end
          end

          C_FROM_PTR: begin
            a_setOffset_i = operand_b_i[IntWidth-1:0];

            alu_operand_a_o = a_getBase_o;
            alu_operand_b_o = operand_b_int;
            alu_operator_o = ALU_ADD;

            result_o = operand_b_i == '0 ? operand_b_i
                     : a_setOffset_o[CheriCapWidth] ? a_setOffset_o[CheriCapWidth-1:0]
                     : {{(CheriCapWidth-IntWidth){1'b0}}, alu_result_i[IntWidth-1:0]};

            wrote_capability = operand_b_i == '0 ? 1'b0
                             : a_setOffset_o[CheriCapWidth] ? 1'b1
                             : 1'b0;

            exceptions_a_o[ TAG_VIOLATION] = operand_b_i != 0 && exceptions_a[ TAG_VIOLATION];
            exceptions_a_o[SEAL_VIOLATION] = operand_b_i != 0 && exceptions_a[SEAL_VIOLATION];

            if (Verbosity) begin
              $display("cfromptr output: %h   exceptions: %h   exceptions_b: %h", result_o, exceptions_a_o, exceptions_b_o);
            end
          end

          C_SUB: begin
            alu_operand_a_o = a_getAddr_o;
            alu_operand_b_o = b_getAddr_o;
            alu_operator_o = ALU_SUB;

            result_o[IntWidth-1:0] = a_getAddr_o - b_getAddr_o;
            wrote_capability = 1'b0;

            if (Verbosity) begin
              $display("csub output: %h   exceptions: %h   exceptions_b: %h", result_o, exceptions_a_o, exceptions_b_o);
            end
          end

          C_BUILD_CAP: begin
            b_setKind_i = a_getKind_o;
            result_o = b_setKind_o | {1'b1, {CheriCapWidth-1{1'b0}}};
            wrote_capability = 1'b1;

            exceptions_a_o[             TAG_VIOLATION] = exceptions_a[ TAG_VIOLATION];
            exceptions_a_o[            SEAL_VIOLATION] = exceptions_a[SEAL_VIOLATION];
            exceptions_a_o[          LENGTH_VIOLATION] = (b_getBase_o < a_getBase_o)
                                                       | (b_getTop_o > a_getTop_o);
            exceptions_a_o[SOFTWARE_DEFINED_VIOLATION] = (a_getPerms_o & b_getPerms_o) != b_getPerms_o;

            // Top is 1 bit longer than base (ie 33 bit when XLEN is 32)
            exceptions_b_o[LENGTH_VIOLATION] = {1'b0, b_getBase_o} > b_getTop_o;

            if (Verbosity) begin
              $display("cbuildcap output: %h   exceptions: %h   exceptions_b: %h", result_o, exceptions_a_o, exceptions_b_o);
            end
          end

          C_COPY_TYPE: begin
            /*
              in implementing this instruction, i've followed this code rather than the one in the sail spec
              this should be functionally equivalent, but i've included it just in case i've made a blunder

              let cb_val = readCapReg(cb);
              let ct_val = readCapReg(ct);
              let cb_base = getCapBase(cb_val);
              let cb_top = getCapTop(cb_val);
              let ct_otype = unsigned(ct_val.otype);
              if not (cb_val.tag) then {
                handle_cheri_reg_exception(CapEx_TagViolation, cb);
                RETIRE_FAIL
              } else if cb_val.sealed then {
                handle_cheri_reg_exception(CapEx_SealViolation, cb);
                RETIRE_FAIL
              } else if ct_val.sealed && ct_otype < cb_base then {
                handle_cheri_reg_exception(CapEx_LengthViolation, cb);
                RETIRE_FAIL
              } else if ct_val.sealed && ct_otype >= cb_top then {
                handle_cheri_reg_exception(CapEx_LengthViolation, cb);
                RETIRE_FAIL
              } else {
                let (success, cap) = setCapOffset(cb_val, to_bits(64, ct_otype - cb_base));
                assert(success, "CopyType: offset is in bounds so should be representable");
                writeCapReg(cd, ct_val.sealed ? cap : int_to_cap(0xffffffffffffffff));
                RETIRE_SUCCESS
              }
            */

            logic b_has_reserved_otype = b_isSealedWithType_o;
            a_setAddr_i = {{(IntWidth-OTypeWidth){1'b0}}, b_getOType_o};
            result_o = b_has_reserved_otype ? a_setAddr_o[CheriCapWidth-1:0]
                                            : {{(CheriCapWidth-OTypeWidth){b_getOType_o[OTypeWidth-1]}}, b_getOType_o};
            wrote_capability = b_has_reserved_otype;

            exceptions_a_o[   TAG_VIOLATION] = exceptions_a[TAG_VIOLATION];
            exceptions_a_o[  SEAL_VIOLATION] = exceptions_a[SEAL_VIOLATION];
            // Not the same as a "common" length violation so we can't use the common case
            exceptions_a_o[LENGTH_VIOLATION] = !b_has_reserved_otype
                                             & ({{(IntWidth-OTypeWidth){1'b0}}, b_getOType_o} < a_getBase_o
                                               |{{(IntWidth-OTypeWidth+1){1'b0}}, b_getOType_o} >= a_getTop_o);

            if (Verbosity) begin
              $display("ccopytype output: %h   exceptions: %h   exceptions_b: %h", result_o, exceptions_a_o, exceptions_b_o);
            end
          end

          C_C_SEAL: begin
            // whether B passes the conditions to seal
            logic b_is_ok = b_isValidCap_o & b_isInBounds_o & b_getAddr_o != {IntWidth{1'b1}};
            a_setKind_cap_i = operand_a_i;
            // TODO this will need to be changed
            a_setKind_i = b_getAddr_o[KindWidth-1:0];
            result_o = !b_is_ok ? operand_a_i : a_setKind_o;
            wrote_capability = 1'b1;

            exceptions_a_o[TAG_VIOLATION] = exceptions_a[TAG_VIOLATION];

            exceptions_b_o[       SEAL_VIOLATION] = b_is_ok && exceptions_b[       SEAL_VIOLATION];
            exceptions_b_o[PERMIT_SEAL_VIOLATION] = b_is_ok && exceptions_b[PERMIT_SEAL_VIOLATION];
            exceptions_b_o[     LENGTH_VIOLATION] = b_is_ok && (exceptions_b[LENGTH_VIOLATION]
                                                               |b_getAddr_o > CheriMaxOType);

            if (Verbosity) begin
              $display("ccseal output: %h   exceptions: %h   exceptions_b: %h", result_o, exceptions_a_o, exceptions_b_o);
            end
          end

          C_TEST_SUBSET: begin
            result_o[0] = a_isValidCap_o != b_isValidCap_o              ? 1'b0
                        : b_getBase_o < a_getBase_o                     ? 1'b0
                        : b_getTop_o > a_getTop_o                       ? 1'b0
                        : (b_getPerms_o & a_getPerms_o) != b_getPerms_o ? 1'b0
                        : 1'b1;
            wrote_capability = 1'b0;

            if (Verbosity) begin
              $display("ctestsubset output: %h   exceptions: %h   exceptions_b: %h", result_o, exceptions_a_o, exceptions_b_o);
            end
          end

          /* This was the old way of implementing CInvoke, which had several
           * versions, and is now no longer used.
          //TWO_SOURCE: begin
            // when trying to read this using the Sail definitions, cs is my operand_a and cb is my operand_b
            //unique case (ccall_type_i)
            //  CCALL_CYCLE1: begin
            //    a_setAddr_i = {a_getAddr_o[IntWidth-1:1], 1'b0};

            //    exceptions_a_o =( exceptions_a[TAG_VIOLATION]                                            ) << TAG_VIOLATION
            //                   |( !exceptions_a[SEAL_VIOLATION]                                          ) << SEAL_VIOLATION // we want it to be sealed
            //                   |( a_getKind_o != b_getKind_o                                             ) << TYPE_VIOLATION
            //                   |( exceptions_a[PERMIT_CCALL_VIOLATION]                                   ) << PERMIT_CCALL_VIOLATION
            //                   |( exceptions_a[PERMIT_EXECUTE_VIOLATION]                                 ) << PERMIT_EXECUTE_VIOLATION
            //                   |( {a_getAddr_o[IntWidth-1:1], 1'b0} < a_getBase_o                   ) << LENGTH_VIOLATION
            //                   |( {a_getAddr_o[IntWidth-1:1], 1'b0} + `MIN_INSTR_BYTES > a_getTop_o ) << LENGTH_VIOLATION;

            //    exceptions_b_o =( exceptions_b[TAG_VIOLATION]             ) << TAG_VIOLATION
            //                   |( !exceptions_b[SEAL_VIOLATION]           ) << SEAL_VIOLATION
            //                   |( !exceptions_b[PERMIT_EXECUTE_VIOLATION] ) << PERMIT_EXECUTE_VIOLATION
            //                   |( exceptions_b[PERMIT_CCALL_VIOLATION]    ) << PERMIT_CCALL_VIOLATION;

            //    a_setKind_cap_i = a_setAddr_o;
            //    a_setKind_i = {KindWidth{1'b1}};
            //    wrote_capability = 1'b1;
            //    result_o = a_setKind_o;
            //  end

            //  CCALL_CYCLE2: begin
            //    a_setAddr_i = {a_getAddr_o[IntWidth-1:1], 1'b0};

            //    exceptions_a_o =( exceptions_a[TAG_VIOLATION]                                            ) << TAG_VIOLATION
            //                   |( !exceptions_a[SEAL_VIOLATION]                                          ) << SEAL_VIOLATION // we want it to be sealed
            //                   |( a_getKind_o != b_getKind_o                                             ) << TYPE_VIOLATION
            //                   |( exceptions_a[PERMIT_CCALL_VIOLATION]                                   ) << PERMIT_CCALL_VIOLATION
            //                   |( exceptions_a[PERMIT_EXECUTE_VIOLATION]                                 ) << PERMIT_EXECUTE_VIOLATION
            //                   |( {a_getAddr_o[IntWidth-1:1], 1'b0} < a_getBase_o                   ) << LENGTH_VIOLATION
            //                   |( {a_getAddr_o[IntWidth-1:1], 1'b0} + `MIN_INSTR_BYTES > a_getTop_o ) << LENGTH_VIOLATION;

            //    exceptions_b_o =( exceptions_b[TAG_VIOLATION]                ) << TAG_VIOLATION
            //                   |( (!exceptions_b[SEAL_VIOLATION]             ) << SEAL_VIOLATION)
            //                   |( ((!exceptions_b[PERMIT_EXECUTE_VIOLATION]) ) << PERMIT_EXECUTE_VIOLATION)
            //                   |( exceptions_b[PERMIT_CCALL_VIOLATION]       ) << PERMIT_CCALL_VIOLATION;

            //    b_setKind_i = {KindWidth{1'b1}};
            //    wrote_capability = 1'b1;
            //    result_o = b_setKind_o;
            //  end
            //endcase
          //end
          */

          SOURCE_AND_DEST: begin
            case(s_a_d_opcode_i)
              C_GET_PERM: begin
                result_o[PermsWidth-1:0] = a_getPerms_o;
                wrote_capability = 1'b0;

                if (Verbosity) begin
                  $display("cgetperm output: %h   exceptions: %h   exceptions_b: %h", result_o, exceptions_a_o, exceptions_b_o);
                end
              end

              C_GET_TYPE: begin
                result_o[IntWidth-1:0] = a_isSealed_o ? {{(IntWidth-OTypeWidth){1'b0}}, a_getOType_o}
                                                      : {IntWidth{1'b1}};
                wrote_capability = 1'b0;

                if (Verbosity) begin
                  $display("cgettype output: %h   exceptions: %h   exceptions_b: %h", result_o, exceptions_a_o, exceptions_b_o);
                end
              end

              C_GET_BASE: begin
                result_o[IntWidth-1:0] = a_getBase_o;
                wrote_capability = 1'b0;

                if (Verbosity) begin
                  $display("cgetbase output: %h   exceptions: %h   exceptions_b: %h", result_o, exceptions_a_o, exceptions_b_o);
                end
              end

              C_GET_LEN: begin
                result_o[IntWidth-1:0] = a_getLength_o[LengthWidth-1] ? {IntWidth{1'b1}}
                                                                      : a_getLength_o[IntWidth-1:0];
                wrote_capability = 1'b0;

                if (Verbosity) begin
                  $display("cgetlen output: %h   exceptions: %h   exceptions_b: %h", result_o, exceptions_a_o, exceptions_b_o);
                end
              end

              C_GET_TAG: begin
                result_o[0] = a_isValidCap_o;
                wrote_capability = 1'b0;

                if (Verbosity) begin
                  $display("cgettag output: %h   exceptions: %h   exceptions_b: %h", result_o, exceptions_a_o, exceptions_b_o);
                end
              end

              C_GET_SEALED: begin
                result_o[0] = a_isSealed_o;
                wrote_capability = 1'b0;

                if (Verbosity) begin
                  $display("cgetsealed output: %h   exceptions: %h   exceptions_b: %h", result_o, exceptions_a_o, exceptions_b_o);
                end
              end

              C_GET_OFFSET: begin
                result_o[IntWidth-1:0] = a_getOffset_o;
                wrote_capability = 1'b0;

                if (Verbosity) begin
                  $display("cgetoffset output: %h   exceptions: %h   exceptions_b: %h", result_o, exceptions_a_o, exceptions_b_o);
                end
              end

              C_GET_FLAGS: begin
                result_o[FlagWidth-1:0] = a_getFlags_o;
                wrote_capability = 1'b0;

                if (Verbosity) begin
                  $display("cgetflags output: %h   exceptions: %h   exceptions_b: %h", result_o, exceptions_a_o, exceptions_b_o);
                end
              end

              C_MOVE: begin
                result_o = operand_a_i;
                wrote_capability = 1'b1;

                if (Verbosity) begin
                  $display("cmove output: %h   exceptions: %h   exceptions_b: %h", result_o, exceptions_a_o, exceptions_b_o);
                end
              end

              C_CLEAR_TAG: begin
                a_setValidCap_i = 1'b0;
                result_o = a_setValidCap_o;
                wrote_capability = 1'b1;

                if (Verbosity) begin
                  $display("ccleartag output: %h   exceptions: %h   exceptions_b: %h", result_o, exceptions_a_o, exceptions_b_o);
                end
              end

              C_JALR: begin
                // current implementation of JAL and JALR:
                // ibex takes 2 cycles to do a normal JAL and JALR, so this one can also take 2 cycles
                // in the first cycle, ibex calculates the jump target and sends it to the IF stage
                // in the second cycle, ibex calculates the old PC + 4 and stores that in the destination
                // register

                // potential implementation of CJALR:
                // we call this instruction here for the first cycle. we do all the exception checking
                // here, and calculate the next PCC from the input register
                // in the second cycle, we just do an incoffsetimm with a = old pcc and b = 4
                // issue is this isn't a very clean way of doing this - we need to fake incoffsetimm instruction
                // in the decoder. However, ibex already does it this way.

                a_setAddr_i = {a_getAddr_o[IntWidth-1:1], 1'b0};
                result_o = a_setAddr_o[CheriCapWidth-1:0];
                wrote_capability = 1'b1;

                alu_operand_a_o = {a_getAddr_o[IntWidth-1:1], 1'b0};
                alu_operand_b_o = 2; // The minimum instruction size in bytes
                alu_operator_o = ALU_ADD;

                exceptions_a_o[           TAG_VIOLATION] = exceptions_a[           TAG_VIOLATION];
                exceptions_a_o[          SEAL_VIOLATION] = exceptions_a[          SEAL_VIOLATION];
                exceptions_a_o[PERMIT_EXECUTE_VIOLATION] = exceptions_a[PERMIT_EXECUTE_VIOLATION];
                exceptions_a_o[        LENGTH_VIOLATION] = exceptions_a[        LENGTH_VIOLATION]
                                                         | (alu_result_i > a_getTop_o);
                // we don't care about trying to throw the last exception since we do support
                // compressed instructions

                if (Verbosity) begin
                  $display("cjalr output: %h   exceptions: %h   exceptions_b: %h", result_o, exceptions_a_o, exceptions_b_o);
                end
              end

              // TODO implement elsewhere
              CLEAR: begin
              end

              C_GET_ADDR: begin
                result_o[IntWidth-1:0] = a_getAddr_o;
                wrote_capability = 1'b0;

                if (Verbosity) begin
                  $display("cgetaddr output: %h   exceptions: %h   exceptions_b: %h", result_o, exceptions_a_o, exceptions_b_o);
                end
              end

              C_SEAL_ENTRY: begin
                a_setKind_cap_i = operand_a_i;
                a_setKind_i = 7'h1E;
                result_o = a_setKind_o;
                wrote_capability = 1'b1;

                exceptions_a_o[           TAG_VIOLATION] = exceptions_a[           TAG_VIOLATION];
                exceptions_a_o[          SEAL_VIOLATION] = exceptions_a[          SEAL_VIOLATION];
                exceptions_a_o[PERMIT_EXECUTE_VIOLATION] = exceptions_a[PERMIT_EXECUTE_VIOLATION];
              end

              default: begin
                //$display("something went wrong in the ibex_alu");
              end
            endcase
          end

          default: begin
            //$display("something went wrong in the ibex_alu");
          end
        endcase
      end

      C_INC_OFFSET_IMM: begin
        // TODO remove adders?
        a_setOffset_i = a_getOffset_o + operand_b_int;
        result_o = a_setOffset_o[CheriCapWidth-1:0];
        // only preserve the tag if the result was "exact"
        result_o[CheriCapWidth-1] = result_o[CheriCapWidth-1] & a_setOffset_o[CheriCapWidth];
        wrote_capability = 1'b1;

        exceptions_a_o[SEAL_VIOLATION] = exceptions_a[SEAL_VIOLATION];

        if (Verbosity) begin
          $display  ("cincoffsetimm output: %h   exceptions: %h   exceptions_b: %h", result_o, exceptions_a_o, exceptions_b_o);
        end
      end

      C_SET_BOUNDS_IMM: begin
        // need to truncate input since we want it to be unsigned
        a_setBounds_i = {{(IntWidth-ImmWidth){1'b0}}, operand_b_int[ImmWidth-1:0]};
        result_o = a_setBounds_o[CheriCapWidth-1:0];
        wrote_capability = 1'b1;

        alu_operand_a_o = a_getAddr_o;
        alu_operand_b_o = {{(IntWidth-ImmWidth){1'b0}}, operand_b_int[ImmWidth-1:0]};
        alu_operator_o = ALU_ADD;

        exceptions_a_o[   TAG_VIOLATION] = exceptions_a[   TAG_VIOLATION];
        exceptions_a_o[  SEAL_VIOLATION] = exceptions_a[  SEAL_VIOLATION];
        exceptions_a_o[LENGTH_VIOLATION] = exceptions_a[LENGTH_VIOLATION]
                                         | alu_result_i > a_getTop_o;

        if (Verbosity) begin
          $display("csetboundsimm output: %h   exceptions: %h   exceptions_b: %h", result_o, exceptions_a_o, exceptions_b_o);
        end
      end

      default: begin
        //$display("something went wrong in the ibex_alu");
      end
    endcase
  end


// TODO rename/rearrange/refactor these

module_wrap64_setBounds module_wrap64_setBounds_a (
      .wrap64_setBounds_cap     (operand_a_i),
      .wrap64_setBounds_length  (a_setBounds_i),
      .wrap64_setBounds         (a_setBounds_o));

module_wrap64_getAddr module_getAddr_a (
      .wrap64_getAddr_cap (operand_a_i),
      .wrap64_getAddr     (a_getAddr_o));

module_wrap64_getAddr module_getAddr_b (
      .wrap64_getAddr_cap (operand_b_i),
      .wrap64_getAddr     (b_getAddr_o));

module_wrap64_getTop module_wrap64_getTop_a (
      .wrap64_getTop_cap  (operand_a_i),
      .wrap64_getTop      (a_getTop_o));

module_wrap64_getTop module_wrap64_getTop_b (
      .wrap64_getTop_cap  (operand_b_i),
      .wrap64_getTop      (b_getTop_o));

// TODO implementing setKind with these modules isn't great since they expect
// a "Kind" as an input, which is not easy to input from Verilog
// since it's a BSV tagged union

// TODO this is hardwired for now - update to not be hardwired later
assign a_setKind_int = a_setKind_i[3:0] == 4'hF ? {3'b000, a_setKind_i[3:0]}
                     : a_setKind_i[3:0] == 4'hE ? {3'b001, a_setKind_i[3:0]}
                     : a_setKind_i[3:0] == 4'hD ? {3'b010, a_setKind_i[3:0]}
                     : a_setKind_i[3:0] == 4'hC ? {3'b011, a_setKind_i[3:0]}
                     : {3'b100, a_setKind_i[3:0]};
module_wrap64_setKind module_wrap64_setKind_a (
      .wrap64_setKind_cap   (a_setKind_cap_i),
      .wrap64_setKind_kind  (a_setKind_int),
      .wrap64_setKind       (a_setKind_o));

module_wrap64_setKind module_wrap64_setKind_b (
      .wrap64_setKind_cap   (operand_b_i),
      .wrap64_setKind_kind  (b_setKind_i),
      .wrap64_setKind       (b_setKind_o));

module_wrap64_getPerms module_wrap64_getPerms_a (
      .wrap64_getPerms_cap  (operand_a_i),
      .wrap64_getPerms      (a_getPerms_o));

module_wrap64_getPerms module_wrap64_getPerms_b (
      .wrap64_getPerms_cap  (operand_b_i),
      .wrap64_getPerms      (b_getPerms_o));


module_wrap64_setPerms module_wrap64_setPerms_a (
      .wrap64_setPerms_cap    (operand_a_i),
      .wrap64_setPerms_perms  (a_setPerms_i),
      .wrap64_setPerms        (a_setPerms_o));

module_wrap64_setPerms module_wrap64_setPerms_b (
      .wrap64_setPerms_cap    (operand_b_i),
      .wrap64_setPerms_perms  (b_setPerms_i),
      .wrap64_setPerms        (b_setPerms_o));

module_wrap64_setFlags module_wrap64_setFlags_a (
      .wrap64_setFlags_cap    (operand_a_i),
      .wrap64_setFlags_flags  (a_setFlags_i),
      .wrap64_setFlags        (a_setFlags_o));

module_wrap64_setOffset module_wrap64_setOffset_a (
      .wrap64_setOffset_cap   (operand_a_i),
      .wrap64_setOffset_offset(a_setOffset_i),
      .wrap64_setOffset       (a_setOffset_o));

module_wrap64_getBase module_getBase_a (
      .wrap64_getBase_cap     (operand_a_i),
      .wrap64_getBase         (a_getBase_o));

module_wrap64_getBase module_getBase_b (
      .wrap64_getBase_cap     (operand_b_i),
      .wrap64_getBase         (b_getBase_o));

module_wrap64_getOffset module_getOffset_a (
      .wrap64_getOffset_cap   (operand_a_i),
      .wrap64_getOffset       (a_getOffset_o));

module_wrap64_getOffset module_getOffset_b (
      .wrap64_getOffset_cap   (operand_b_i),
      .wrap64_getOffset       (b_getOffset_o));

module_wrap64_isValidCap module_wrap64_isValidCap_a (
      .wrap64_isValidCap_cap  (operand_a_i),
      .wrap64_isValidCap      (a_isValidCap_o));

module_wrap64_isValidCap module_wrap64_isValidCap_b (
      .wrap64_isValidCap_cap  (operand_b_i),
      .wrap64_isValidCap      (b_isValidCap_o));

module_wrap64_getKind module_wrap64_getKind_a (
      .wrap64_getKind_cap     (operand_a_i),
      .wrap64_getKind         (a_getKind_o));

module_wrap64_getKind module_wrap64_getKind_b (
      .wrap64_getKind_cap     (operand_b_i),
      .wrap64_getKind         (b_getKind_o));

module_wrap64_getLength module_getLength_a (
      .wrap64_getLength_cap   (operand_a_i),
      .wrap64_getLength       (a_getLength_o));

module_wrap64_getFlags module_getFlags_a (
      .wrap64_getFlags_cap    (operand_a_i),
      .wrap64_getFlags        (a_getFlags_o));

module_wrap64_setValidCap module_wrap64_setValidCap_a (
      .wrap64_setValidCap_cap   (operand_a_i),
      .wrap64_setValidCap_valid (a_setValidCap_i),
      .wrap64_setValidCap       (a_setValidCap_o));

module_wrap64_setValidCap module_wrap64_setValidCap_b (
      .wrap64_setValidCap_cap   (operand_b_i),
      .wrap64_setValidCap_valid (b_setValidCap_i),
      .wrap64_setValidCap       (b_setValidCap_o));

module_wrap64_setAddr module_wrap64_setAddr_a (
      .wrap64_setAddr_cap       (operand_a_i),
      .wrap64_setAddr_addr      (a_setAddr_i),
      .wrap64_setAddr           (a_setAddr_o));

module_wrap64_setAddr module_wrap64_setAddr_b (
      .wrap64_setAddr_cap   (operand_b_i),
      .wrap64_setAddr_addr  (b_setAddr_i),
      .wrap64_setAddr       (b_setAddr_o));

module_wrap64_isInBounds module_isInBounds_a (
      .wrap64_isInBounds_cap (operand_a_i),
      .wrap64_isInBounds_isTopIncluded(a_isInBounds_isTopIncluded_i),
      .wrap64_isInBounds (a_isInBounds_o));

module_wrap64_isInBounds module_isInBounds_b (
      .wrap64_isInBounds_cap (operand_b_i),
      .wrap64_isInBounds_isTopIncluded(b_isInBounds_isTopIncluded_i),
      .wrap64_isInBounds (b_isInBounds_o));


  // TODO
  // strictly speaking, some of the exceptions that are being set after isSealed and
  // isValidCap would need to be &&'d with the negative of the ones above them
  // (ie a_isValidCap_o && !a_isSealed_o && a_CURSOR_o < a_isSealed_o)
  // this may not actually be needed because exceptions have priorities

  // check for common violations
  always_comb begin
    exceptions_a = 0;
    exceptions_b = 0;

    if (!a_isValidCap_o)
      exceptions_a[TAG_VIOLATION] = 1'b1;

    if (!b_isValidCap_o)
      exceptions_b[TAG_VIOLATION] = 1'b1;

    if (a_isValidCap_o && a_isSealed_o)
      exceptions_a[SEAL_VIOLATION] = 1'b1;

    if (b_isValidCap_o && b_isSealed_o)
      exceptions_b[SEAL_VIOLATION] = 1'b1;

    if (a_getAddr_o < a_getBase_o)
      exceptions_a[LENGTH_VIOLATION] = 1'b1;

    if (b_getAddr_o < b_getBase_o)
      exceptions_b[LENGTH_VIOLATION] = 1'b1;

    if (a_getKind_o != b_getKind_o)
      exceptions_a[TYPE_VIOLATION] = 1'b1;

    if (!b_getPerms_o[PermitUnsealIndex])
      exceptions_b[PERMIT_UNSEAL_VIOLATION] = 1'b1;

    if (!b_getPerms_o[PermitSealIndex])
      exceptions_b[PERMIT_SEAL_VIOLATION] = 1'b1;

    if (!a_getPerms_o[PermitExecuteIndex])
      exceptions_a[PERMIT_EXECUTE_VIOLATION] = 1'b1;

    if (!b_getPerms_o[PermitExecuteIndex])
      exceptions_b[PERMIT_EXECUTE_VIOLATION] = 1'b1;

    if (!a_getPerms_o[PermitCInvokeIndex])
      exceptions_a[PERMIT_CCALL_VIOLATION] = 1'b1;

    if (!b_getPerms_o[PermitCInvokeIndex])
      exceptions_b[PERMIT_CCALL_VIOLATION] = 1'b1;

  end
endmodule
