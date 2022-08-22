#include "Vibex_top_sram.h"
#include <iostream>
#include "verilated_fst_c.h"

double main_time = 0;

double sc_time_stamp() {
    return main_time;
}

// Barebones main function which just loops the core
int main(int argc, char** argv, char** env) {

    Verilated::commandArgs(argc, argv);
    Vibex_top_sram * top = new Vibex_top_sram;

    top->eval();

    top->eval();

    // TODO set up initial boot address
    //top->boot_addr_i = 0x80000000;
    top->clk_i = 1;
    top->rst_ni = 1;
    top->test_en_i = 1;
    top->fetch_enable_i = 1;
    top-> eval();

    // set up instruction (NOP)
    top->instr_gnt_i = 1;
    top->instr_rvalid_i = 1;
    top->instr_rdata_i = 0x00000013;
    top->instr_rdata_intg_i = 0;
    top->instr_err_i = 0;

    // set up tracing
    #if VM_TRACE
    Verilated::traceEverOn(true);
    VerilatedFstC* trace_obj = new VerilatedFstC;
    top->trace(trace_obj, 99);
    trace_obj->open("vlt_d.vcd");
    #endif

    while (1) {
        main_time++;
        top->clk_i = !top->clk_i;
        top->eval();
        trace_obj->dump(main_time);
        std::cout << "instr req: " << std::hex << top->instr_req_o << std::endl;
        std::cout << "instr addr: " << std::hex << top->instr_addr_o << std::endl;
    }

    std::cout << "finished" << std::endl << std::flush;
    delete top;
    exit(0);
}

