`timescale 1ns / 1ps

class transaction_item;
    bit rstn;
    rand bit [31:0]din;
    bit wr_en;
    bit rd_en;
    bit en;
    bit [31:0] dout;
    bit full;
    bit empty;
   
    function void print();
        $display("Values: a=0x%0h, b=0x%0h, result=0x%0h, carry=0x%0h",a, b, result, carry);
    endfunction

    function void copy(transaction_item tmp);
        this.rstn = tmp.rstn;
        this.din = tmp.din;
        this.wr_en = tmp.wr_en;
        this.rd_en = tmp.rd_en;
        this.en = tmp.en;
        this.dout = tmp.dout;
        this.full = tmp.full;
        this.empty = tmp.empty;
  endfunction
endclass

//-----------------------
// INTERFACE
// ----------------------
interface intf(input bit clk);
  logic rstn;
  logic [31:0] din;
  logic wr_en, rd_en, en;
  logic full, empty;
  logic [31:0] dout;

  // Driver Clocking Block: Outputs from TB -> Inputs to DUT
  clocking driver_cb @(posedge clk);
//    default input #1step output #1ns;
    default input #1step;
    output rstn, din, wr_en, rd_en, en;
  endclocking

  // Monitor Clocking Block: Inputs to TB <- Outputs from DUT
  clocking monitor_cb @(posedge clk);
//    default input #1step output #1ns;
    default input #1step;
    input rstn, din, wr_en, rd_en, en, full, empty, dout;
  endclocking

  // Modports to restrict direction
  modport DRV (clocking driver_cb, input clk);
  modport MON (clocking monitor_cb, input clk);
  
  // SVA 1: Reset Assertion (Active Low Reset forces outputs to 0 on next posedge)
    property p_reset_check;
        @(posedge clk) !rstn |=> (dout == 32'h0000);
    endproperty
    a_reset_check: assert property(p_reset_check)
        else $error("SVA Error: Reset failed to clear outputs!");

    // SVA 2: Operation Stability Check (Outputs shouldn't be X/Z when reset is released)
    property p_no_unknowns;
        @(posedge clk) disable iff (!rstn) !$isunknown(dout);
    endproperty
    a_no_unknowns: assert property(p_no_unknowns)
        else $error("SVA Error: Data_out driving X or Z!");
    
    //
    
endinterface

//-----------------------
// GENERATOR
// ----------------------
class generator;
  event drv_done;
  event gen_cmpltd;
  mailbox drv_mbx;
  
  task run();
    for (int i = 0; i < 128; i++) begin
        transaction_item item = new();
        
        item.rstn = 1'b1; // Default to active high operational mode
        item.din = i;
        if( i < 'd64) begin
            item.wr_en = 1;
        end 
        else begin
            item.rd_en = 1;
        end 
        item.en = 1;
        
        drv_mbx.put(item);
        @(drv_done);
     end
     -> gen_cmpltd;
  endtask
endclass



//----------------------------------
// TESTBENCH TOP
//----------------------------------

module testbench();
    reg clk;
    initial begin
        clk = 0;
        intf.rstn = 0;
        forever begin
            #10 clk = ~clk;
        end
    end

    intf intf(clk);

    fifo u0(
        .clk(intf.clk),
        .rstn(intf.rstn),
        .din(intf.din),
        .wr_en(intf.wr_en),
        .rd_en(intf.rd_en),
        .en(intf.en),
        .full(intf.full),
        .empty(intf.empty),
        .dout(intf.dout)
    );

    test t0;
    initial begin
        t0 = new;
        t0.e0.vif = intf;

        t0.run();

        $display("==============================");
        $display("FUNCTIONAL COVERAGE");
        $display("==============================");
        
        $display("==============================");
        
        $finish;
    end
endmodule
