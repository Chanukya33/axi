interface axi_lite_if(input logic ACLK);
    logic ARESET;
    logic [31:0] AWADDR, WDATA, ARADDR, RDATA;
    logic AWVALID, AWREADY, WVALID, WREADY, BVALID, BREADY;
    logic ARVALID, ARREADY, RVALID, RREADY;
    logic [1:0]  BRESP, RRESP;
endinterface

class transaction;
    rand bit [31:0] addr;
    rand bit [31:0] wdata;
    rand bit        is_write;  
    bit [31:0]      rdata;
    bit [1:0]       resp;
    void display(string name);
            $display("[%s] WRITE Addr: %0d | WData: %0h | Resp: %0d  READ RData: %0h ", name, addr, wdata, resp, rdata);
    endfunction
    endclass

class parent;
    transaction tr;
    int num_transactions;
    mailbox #(transaction) gen2drv;
    mailbox #(transaction) mon2scb;
    virtual axi_lite_if inf;
endclass

class generator extends parent;
    function new(mailbox #(transaction) gen2drv, int num_transactions);
        this.gen2drv = gen2drv;
        this.num_transactions = num_transactions;
    endfunction

    task run();
        repeat(num_transactions) begin
            tr = new();
            void'(tr.randomize());
            tr.display("GENERATOR");
            gen2drv.put(tr);
        end
    endtask
endclass

class driver extends parent;
    function new(mailbox #(transaction) gen2drv, int num_transactions, virtual axi_lite_if inf);
        this.gen2drv = gen2drv;
        this.num_transactions = num_transactions;
        this.inf = inf;
    endfunction

    task run();
        inf.AWVALID = 0; inf.WVALID = 0; inf.BREADY = 0;
        inf.ARVALID = 0; inf.RREADY = 0;
        inf.AWADDR = 0;  inf.WDATA = 0;  inf.ARADDR = 0;
        wait(inf.ARESET == 1'b0);
        repeat(num_transactions) begin
            tr = new();
            gen2drv.get(tr);
            repeat(2) @(posedge inf.ACLK);
            
            if (tr.is_write) begin
                fork
                    begin
                        repeat(2) @(posedge inf.ACLK);
                        inf.AWADDR  = tr.addr;
                        inf.AWVALID = 1;
                        wait(inf.AWREADY);
                        @(posedge inf.ACLK);
                        inf.AWVALID = 0;
                    end
                    begin
                        repeat(2) @(posedge inf.ACLK);
                        inf.WDATA   = tr.wdata;
                        inf.WVALID  = 1;
                        wait(inf.WREADY);
                        @(posedge inf.ACLK);
                        inf.WVALID  = 0;
                    end
                join

                repeat(2) @(posedge inf.ACLK);
                inf.BREADY = 1;
                wait(inf.BVALID);
                @(posedge inf.ACLK);
                inf.BREADY = 0;
            end 
            else begin
                repeat(2) @(posedge inf.ACLK);
                inf.ARADDR  = tr.addr;
                inf.ARVALID = 1;
                wait(inf.ARREADY);
                @(posedge inf.ACLK);
                inf.ARVALID = 0;

                repeat(2) @(posedge inf.ACLK);
                inf.RREADY = 1;
                wait(inf.RVALID);
                @(posedge inf.ACLK);
                inf.RREADY = 0;
            end
            tr.display("DRIVER");
        end
    endtask
endclass

class monitor extends parent;
    function new(mailbox #(transaction) mon2scb, int num_transactions, virtual axi_lite_if inf);
        this.mon2scb = mon2scb;
        this.num_transactions = num_transactions;
        this.inf = inf;
    endfunction

    task run();
        repeat(num_transactions) begin
            tr = new();
            do begin
                @(posedge inf.ACLK);
                if (inf.AWVALID && inf.AWREADY) begin
                    tr.is_write = 1;
                    tr.addr = inf.AWADDR;
                end
                if (inf.WVALID && inf.WREADY) begin
                    tr.wdata = inf.WDATA;
                end
                if (inf.ARVALID && inf.ARREADY) begin
                    tr.is_write = 0;
                    tr.addr = inf.ARADDR;
                end
            end while (!(inf.BVALID && inf.BREADY) && !(inf.RVALID && inf.RREADY));
            if (inf.BVALID && inf.BREADY) tr.resp = inf.BRESP;
            if (inf.RVALID && inf.RREADY) begin
                tr.rdata = inf.RDATA;
                tr.resp  = inf.RRESP;
            end
            
            tr.display("MONITOR");
            mon2scb.put(tr);
        end
    endtask
endclass

class scoreboard extends parent;
    bit [31:0] ref_mem [32];
    int pass = 0;
    int fail = 0;
    int trans_local = 0;

    function new(mailbox #(transaction) mon2scb, int num_transactions);
        this.mon2scb = mon2scb;
        this.num_transactions = num_transactions;
    endfunction

    task run();
        foreach(ref_mem[i]) ref_mem[i] = 0;
        repeat(num_transactions) begin
            mon2scb.get(tr);          
            if (tr.is_write) begin
                ref_mem[tr.addr] = tr.wdata;
                if (tr.resp == 2'b00) begin
                    $display("TRANSACTION SUCCESFULL (WRITE to addr %0d)", tr.addr);
                    pass++;
                end else begin
                    $display("TRANSACTION UNSUCCESFULL (WRITE to addr %0d): Error Resp %0d", tr.addr, tr.resp);
                    fail++;
                end
                trans_local++;
            end else begin
                if (tr.rdata == ref_mem[tr.addr] && tr.resp == 2'b00) begin
                    $display("TRANSACTION SUCCESFULL (READ from addr %0d)", tr.addr);
                    pass++;
                end else begin
                    $display("TRANSACTION UNSUCCESFULL (READ from addr %0d): Read %0h Expected %0h, Resp %0d", tr.addr, tr.rdata, ref_mem[tr.addr], tr.resp);
                    fail++;
                end
                trans_local++;
            end
        end
        $display("=========================================");
        $display("        SUMMARY REPORT    ");
        $display("         PASS COUNT : %0d", pass);
        $display("         FAIL COUNT : %0d", fail);
        $display("         TRANS COUNT : %0d", trans_local);
        $display("=========================================");
    endtask
endclass

class environment;
    mailbox #(transaction) gen2drv, mon2scb;
    virtual axi_lite_if vif;
    int num;
    generator gen;
    driver drv;
    monitor mon;
    scoreboard scb;

    function new(int num, virtual axi_lite_if vif);
        gen2drv = new();
        mon2scb = new();
        this.num = num;
        this.vif = vif;
        gen = new(gen2drv, num);
        drv = new(gen2drv, num, vif);
        mon = new(mon2scb, num, vif);
        scb = new(mon2scb, num);
    endfunction

    task run();
        fork
            gen.run();
            drv.run();
            mon.run();
            scb.run();
        join
    endtask
endclass

module top_tb;
    bit clk;
    int num = 100; 

    always #10 clk = ~clk;

    axi_lite_if vif(clk);

    axi_lite_block uut (.ACLK(vif.ACLK), .ARESET(vif.ARESET), .AWVALID(vif.AWVALID), .WVALID(vif.WVALID), .BREADY(vif.BREADY), .ARVALID(vif.ARVALID), 
        .RREADY(vif.RREADY), .AWADDR(vif.AWADDR), .WDATA(vif.WDATA), .ARADDR(vif.ARADDR),.AWREADY(vif.AWREADY), READY(vif.WREADY), .BVALID(vif.BVALID), 
        .RVALID(vif.RVALID), .ARREADY(vif.ARREADY),.RDATA(vif.RDATA), RRESP(vif.RRESP), .BRESP(vif.BRESP)
    );

    environment env;
    initial begin
        env = new(num, vif);
        vif.ARESET = 1;
        #25 vif.ARESET = 0;        
        env.run();
        $finish;
    end
endmodule
