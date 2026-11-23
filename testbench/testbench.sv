`timescale 1ns/1ps

//====================================================
// TRANSACTION
//====================================================
class transaction_item;
    bit rstn;
    rand bit [31:0] din;
    bit wr_en, rd_en, en;
    bit [31:0] dout;
    bit full, empty;
    integer case_id;
    string case_name;

    function void print();
        $display("[%0t] rstn=%b en=%b wr=%b rd=%b din=%h dout=%h full=%b empty=%b",
                 $time, rstn, en, wr_en, rd_en, din, dout, full, empty);
    endfunction

    function void copy(transaction_item rhs);
        rstn=rhs.rstn; din=rhs.din; wr_en=rhs.wr_en;
        rd_en=rhs.rd_en; en=rhs.en; dout=rhs.dout;
        full=rhs.full; empty=rhs.empty; case_id=rhs.case_id; case_name=rhs.case_name;
    endfunction
endclass


//====================================================
// INTERFACE + SVA ASSERTIONS
//====================================================
interface intf(input logic clk);
    logic rstn;
    logic [31:0] din;
    logic wr_en, rd_en, en;
    logic full, empty;
    logic [31:0] dout;
    integer case_id;

    clocking driver_cb @(negedge clk);
        output rstn, din, wr_en, rd_en, en, case_id;
    endclocking

    clocking monitor_cb @(posedge clk);
        // Sample after the DUT's nonblocking assignments have settled.
        input #1ns rstn, din, wr_en, rd_en, en, full, empty, dout;
    endclocking

    modport DRV(clocking driver_cb, input clk);
    modport MON(
        clocking monitor_cb,
        input clk, case_id,
        rstn, din, wr_en, rd_en, en, full, empty, dout
    );

    // SVA 1: Active-low reset clears output and status.
    property p_reset_check;
        @(posedge clk) !rstn |=> (dout == 32'h0 && empty && !full);
    endproperty
    a_reset_check: assert property(p_reset_check)
        else $error("SVA: reset did not clear FIFO output/status");

    // SVA 2: No unknowns after reset is released.
    property p_no_unknowns;
        @(posedge clk) disable iff (!rstn)
            !$isunknown({dout, full, empty});
    endproperty
    a_no_unknowns: assert property(p_no_unknowns)
        else $error("SVA: FIFO output/status contains X or Z");

    // SVA 3: FULL and EMPTY must never be asserted together.
    property p_full_empty_exclusive;
        @(posedge clk) disable iff (!rstn)
            !(full && empty);
    endproperty
    a_full_empty_exclusive: assert property(p_full_empty_exclusive)
        else $error("SVA: FULL and EMPTY asserted together");

    // SVA 4: A write-only request while full must keep FIFO full.
    // At full, write is rejected; with no read, occupancy stays full.
    property p_reject_write_when_full;
        @(posedge clk) disable iff (!rstn)
            (full && en && wr_en && !rd_en) |=> full;
    endproperty
    a_reject_write_when_full: assert property(p_reject_write_when_full)
        else $error("SVA: FIFO did not remain full after rejected write");

    // SVA 5: A read-only request while empty must keep FIFO empty.
    property p_reject_read_when_empty;
        @(posedge clk) disable iff (!rstn)
            (empty && en && rd_en && !wr_en) |=> empty;
    endproperty
    a_reject_read_when_empty: assert property(p_reject_read_when_empty)
        else $error("SVA: FIFO did not remain empty after rejected read");

    // SVA 6: When no read is accepted, registered dout must hold.
    // $stable compares dout against its value on the previous clock.
    property p_dout_holds_without_read;
        @(posedge clk) disable iff (!rstn)
            !(en && rd_en && !empty) |=> $stable(dout);
    endproperty
    a_dout_holds_without_read: assert property(p_dout_holds_without_read)
        else $error("SVA: dout changed without an accepted read");

    // SVA 7: An accepted read must make dout update on the following
    // sampled clock. This checks registered-read activity; data ordering
    // and the exact value are checked by the queue scoreboard.
    property p_dout_read_activity;
        @(posedge clk) disable iff (!rstn)
            ($past(rstn) && $past(en) && $past(rd_en) && !$past(empty))
            |-> !$isunknown(dout);
    endproperty
    a_dout_read_activity: assert property(p_dout_read_activity)
        else $error("SVA: dout unknown after accepted read");

endinterface


//====================================================
// GENERATOR
//====================================================
class generator;
    mailbox #(transaction_item) drv_mbx;
    event drv_done;
    event gen_completed;

    function new(mailbox #(transaction_item) mbx, event done_ev);
        drv_mbx=mbx;
        drv_done=done_ev;
    endfunction

    task send(transaction_item item, string case_name);
        item.case_name = case_name;
        item.case_id = label_to_id(case_name);
        drv_mbx.put(item);
        @drv_done;
    endtask

    function automatic integer label_to_id(input string label);
        case (label)
            "RESET": label_to_id=1;
            "SINGLE_WRITE": label_to_id=2;
            "SINGLE_READ": label_to_id=3;
            "RESET_BEFORE_BOUNDARY": label_to_id=4;
            "FILL_TO_FULL": label_to_id=5;
            "WRITE_WHILE_FULL": label_to_id=6;
            "DRAIN_FIFO": label_to_id=7;
            "READ_WHILE_EMPTY": label_to_id=8;
            "DISABLE_HOLDS_FIFO": label_to_id=9;
            "IDLE_HOLD": label_to_id=10;
            "RESET_FOR_SIMULTANEOUS": label_to_id=11;
            "SIMULTANEOUS_SETUP": label_to_id=12;
            "SIMULTANEOUS_READ_WRITE": label_to_id=13;
            "SIMULTANEOUS_DRAIN": label_to_id=14;
            default: label_to_id=0;
        endcase
    endfunction

    task run();
        transaction_item item;

        // CASE 1: Reset
        item=new();
        item.rstn=0; item.en=0; item.wr_en=0;
        item.rd_en=0; item.din=0;
        send(item, "RESET");

        // CASE 2: Basic write/read data integrity
        item=new();
        item.rstn=1; item.en=1; item.wr_en=1; item.rd_en=0;
        item.din=32'hA5A5_1234;
        send(item, "SINGLE_WRITE");

        item=new();
        item.rstn=1; item.en=1; item.wr_en=0; item.rd_en=1;
        item.din=0;
        send(item, "SINGLE_READ");

        // Reset before boundary tests
        item=new();
        item.rstn=0; item.en=0; item.wr_en=0; item.rd_en=0; item.din=0;
        send(item, "RESET_BEFORE_BOUNDARY");

        // CASE 3: Fill FIFO until FULL
        for (int i=0; i<128; i++) begin
            item=new();
            item.rstn=1; item.en=1;
            item.wr_en=1; item.rd_en=0;
            item.din=i;
            send(item, "FILL_TO_FULL");
        end

        // CASE 4: Negative stimulus - write while full must be rejected
        item=new();
        item.rstn=1; item.en=1; item.wr_en=1;
        item.rd_en=0; item.din=32'hDEAD_BEEF;
        send(item, "WRITE_WHILE_FULL");

        // CASE 5: Drain FIFO; verify FIFO ordering
        for (int i=0; i<128; i++) begin
            item=new();
            item.rstn=1; item.en=1;
            item.wr_en=0; item.rd_en=1;
            item.din=0;
            send(item, "DRAIN_FIFO");
        end

        // CASE 6: Negative stimulus - read while empty must be rejected
        item=new();
        item.rstn=1; item.en=1; item.wr_en=0;
        item.rd_en=1; item.din=0;
        send(item, "READ_WHILE_EMPTY");

        // CASE 7: Enable low - write request must be ignored
        item=new();
        item.rstn=1; item.en=0; item.wr_en=1;
        item.rd_en=0; item.din=32'h1234;
        send(item, "DISABLE_HOLDS_FIFO");

        // CASE 8: Idle cycle - output/status should hold
        item=new();
        item.rstn=1; item.en=1; item.wr_en=0;
        item.rd_en=0; item.din=0;
        send(item, "IDLE_HOLD");

        // CASE 9: Simultaneous read and write at non-empty occupancy
        item=new();
        item.rstn=0; item.en=0; item.wr_en=0; item.rd_en=0; item.din=0;
        send(item, "RESET_FOR_SIMULTANEOUS");

        item=new();
        item.rstn=1; item.en=1; item.wr_en=1; item.rd_en=0;
        item.din=32'h11;
        send(item, "SIMULTANEOUS_SETUP");

        item=new();
        item.rstn=1; item.en=1; item.wr_en=1; item.rd_en=0;
        item.din=32'h22;
        send(item, "SIMULTANEOUS_SETUP");

        item=new();
        item.rstn=1; item.en=1; item.wr_en=1; item.rd_en=1;
        item.din=32'h33;
        send(item, "SIMULTANEOUS_READ_WRITE");

        item=new();
        item.rstn=1; item.en=1; item.wr_en=0; item.rd_en=1; item.din=0;
        send(item, "SIMULTANEOUS_DRAIN");

        item=new();
        item.rstn=1; item.en=1; item.wr_en=0; item.rd_en=1; item.din=0;
        send(item, "SIMULTANEOUS_DRAIN");

        ->gen_completed;
    endtask
endclass


//====================================================
// DRIVER
//====================================================
class driver;
    virtual intf.DRV vif;
    mailbox #(transaction_item) drv_mbx;
    event drv_done;
    bit stop;

    function new(virtual intf.DRV vif,
                mailbox #(transaction_item) mbx,
                event done_ev);
        this.vif=vif;
        drv_mbx=mbx;
        drv_done=done_ev;
        stop=0;
    endfunction

    task run();
        transaction_item item;
        while (!stop) begin
            drv_mbx.get(item);
            @(vif.driver_cb);
            vif.driver_cb.rstn  <= item.rstn;
            vif.driver_cb.din   <= item.din;
            vif.driver_cb.wr_en <= item.wr_en;
            vif.driver_cb.rd_en <= item.rd_en;
            vif.driver_cb.en    <= item.en;
            vif.driver_cb.case_id <= item.case_id;
            // Complete after the DUT has sampled the driven cycle.
            @(posedge vif.clk);
            ->drv_done;
        end
    endtask
endclass


//====================================================
// MONITOR
//====================================================
class monitor;
    virtual intf.MON vif;
    mailbox #(transaction_item) mon_mbx;
    bit stop;

    function new(virtual intf.MON vif, mailbox #(transaction_item) mbx);
        this.vif=vif;
        mon_mbx=mbx;
        stop=0;
    endfunction

    // Decode the integer case tag locally. The scoreboard's method is
    // class-scoped and cannot be called directly from this monitor class.
    function automatic string id_to_label(input integer id);
        case (id)
            1: id_to_label="RESET";
            2: id_to_label="SINGLE_WRITE";
            3: id_to_label="SINGLE_READ";
            4: id_to_label="RESET_BEFORE_BOUNDARY";
            5: id_to_label="FILL_TO_FULL";
            6: id_to_label="WRITE_WHILE_FULL";
            7: id_to_label="DRAIN_FIFO";
            8: id_to_label="READ_WHILE_EMPTY";
            9: id_to_label="DISABLE_HOLDS_FIFO";
            10: id_to_label="IDLE_HOLD";
            11: id_to_label="RESET_FOR_SIMULTANEOUS";
            12: id_to_label="SIMULTANEOUS_SETUP";
            13: id_to_label="SIMULTANEOUS_READ_WRITE";
            14: id_to_label="SIMULTANEOUS_DRAIN";
            default: id_to_label="UNLABELLED";
        endcase
    endfunction

    task run();
        transaction_item item;
        while (!stop) begin
            // Wait for the active clock edge, then sample after DUT NBA updates.
            @(posedge vif.clk);
            #1ns;
            item=new();
            item.rstn=vif.rstn;
            item.din=vif.din;
            item.wr_en=vif.wr_en;
            item.rd_en=vif.rd_en;
            item.en=vif.en;
            item.full=vif.full;
            item.empty=vif.empty;
            item.dout=vif.dout;
            item.case_name=id_to_label(vif.case_id);
            mon_mbx.put(item);
        end
    endtask
endclass


//====================================================
// SCOREBOARD / FIFO REFERENCE MODEL
//====================================================
class scoreboard;
    mailbox #(transaction_item) mon_mbx;
    bit [31:0] model_q[$];
    bit [31:0] expected_dout;
    int checks, errors;
    int case_count, passed_cases, failed_cases;
    string active_case;
    int errors_at_case_start;

    function new(mailbox #(transaction_item) mbx);
        mon_mbx=mbx;
        checks=0;
        errors=0;
        expected_dout=0;
        case_count=0; passed_cases=0; failed_cases=0;
        active_case=""; errors_at_case_start=0;
    endfunction

    function automatic string id_to_label(input integer id);
        case (id)
            1: id_to_label="RESET";
            2: id_to_label="SINGLE_WRITE";
            3: id_to_label="SINGLE_READ";
            4: id_to_label="RESET_BEFORE_BOUNDARY";
            5: id_to_label="FILL_TO_FULL";
            6: id_to_label="WRITE_WHILE_FULL";
            7: id_to_label="DRAIN_FIFO";
            8: id_to_label="READ_WHILE_EMPTY";
            9: id_to_label="DISABLE_HOLDS_FIFO";
            10: id_to_label="IDLE_HOLD";
            11: id_to_label="RESET_FOR_SIMULTANEOUS";
            12: id_to_label="SIMULTANEOUS_SETUP";
            13: id_to_label="SIMULTANEOUS_READ_WRITE";
            14: id_to_label="SIMULTANEOUS_DRAIN";
            default: id_to_label="UNLABELLED";
        endcase
    endfunction

    task run();
        transaction_item item;
        bit do_write, do_read;
        bit [31:0] popped;

        forever begin
            mon_mbx.get(item);

            if (item.case_name != active_case) begin
                if (active_case != "") begin
                    case_count++;
                    if (errors == errors_at_case_start) begin
                        passed_cases++;
                        $display("  PASS: %s", active_case);
                    end
                    else begin
                        failed_cases++;
                        $display("  FAIL: %s (%0d error(s))",
                                 active_case, errors-errors_at_case_start);
                    end
                end
                active_case=item.case_name;
                errors_at_case_start=errors;
            end

            if (!item.rstn) begin
                model_q.delete();
                expected_dout=0;
            end
            else begin
                // Acceptance is based on pre-edge model occupancy.
                do_write=item.en && item.wr_en && (model_q.size()<128);
                do_read =item.en && item.rd_en && (model_q.size()>0);

                // DUT reads old queue content on a simultaneous operation.
                if (do_read) begin
                    popped=model_q.pop_front();
                    expected_dout=popped;
                end

                if (do_write)
                    model_q.push_back(item.din);
            end

            checks++;

            if (item.dout !== expected_dout) begin
                $error("[%0t] DATA mismatch actual=%h expected=%h",
                       $time,item.dout,expected_dout);
                errors++;
            end

            if (item.full !== (model_q.size()==128)) begin
                $error("[%0t] FULL mismatch actual=%b expected=%b",
                       $time,item.full,(model_q.size()==128));
                errors++;
            end

            if (item.empty !== (model_q.size()==0)) begin
                $error("[%0t] EMPTY mismatch actual=%b expected=%b",
                       $time,item.empty,(model_q.size()==0));
                errors++;
            end
        end
    endtask

    function void finish_cases();
        if (active_case != "") begin
            case_count++;
            if (errors == errors_at_case_start) begin
                passed_cases++;
                $display("  PASS: %s", active_case);
            end
            else begin
                failed_cases++;
                $display("  FAIL: %s (%0d error(s))",
                         active_case, errors-errors_at_case_start);
            end
            active_case="";
        end
    endfunction
endclass


//====================================================
// ENVIRONMENT
//====================================================
class environment;
    virtual intf vif;

    mailbox #(transaction_item) drv_mbx;
    mailbox #(transaction_item) mon_mbx;
    event drv_done;

    generator g0;
    driver d0;
    monitor m0;
    scoreboard s0;

    function new();
        drv_mbx=new();
        mon_mbx=new();
    endfunction

    task build();
        g0=new(drv_mbx,drv_done);
        d0=new(vif.DRV,drv_mbx,drv_done);
        m0=new(vif.MON,mon_mbx);
        s0=new(mon_mbx);
    endtask

    task run();
        fork
            g0.run();
            d0.run();
            m0.run();
            s0.run();
        join_none

        @g0.gen_completed;
        repeat(3) @(posedge vif.clk);

        d0.stop=1;
        m0.stop=1;
        s0.finish_cases();

        $display("\n========== FIFO SCOREBOARD ==========");
        $display("Samples checked : %0d",s0.checks);
        $display("Errors          : %0d",s0.errors);
        $display("Cases passed    : %0d",s0.passed_cases);
        $display("Cases failed    : %0d",s0.failed_cases);
        if (s0.errors==0 && s0.failed_cases==0)
            $display("OVERALL RESULT: PASS");
        else
            $display("OVERALL RESULT: FAIL");
        $display("====================================\n");
    endtask
endclass


//====================================================
// TEST
//====================================================
class test;
    environment e0;

    function new();
        e0=new();
    endfunction

    task run();
        e0.build();
        e0.run();
    endtask
endclass


//====================================================
// TOP
//====================================================
module testbench;
    bit clk=0;
    always #5 clk=~clk;

    intf intf(clk);

    fifo #(.width(32),.depth(128)) u0 (
        .clk(clk),
        .rstn(intf.rstn), // active-low reset
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
        intf.rstn=0;
        intf.din=0;
        intf.wr_en=0;
        intf.rd_en=0;
        intf.en=0;
        intf.case_id=0;

        t0=new();
        t0.e0.vif=intf;
        t0.run();
        $finish;
    end
endmodule
