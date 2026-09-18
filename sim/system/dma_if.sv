`timescale 1ns/1ps

interface axi_lite_if(input logic ACLK);
    logic        ARESETN;

    logic [6:0]  AWADDR;
    logic        AWVALID;
    logic        AWREADY;
    logic [31:0] WDATA;
    logic [3:0]  WSTRB;
    logic        WVALID;
    logic        WREADY;
    logic [1:0]  BRESP;
    logic        BVALID;
    logic        BREADY;

    logic [6:0]  ARADDR;
    logic        ARVALID;
    logic        ARREADY;
    logic [31:0] RDATA;
    logic [1:0]  RRESP;
    logic        RVALID;
    logic        RREADY;

    int unsigned protocol_errors;

    task automatic init_master();
        AWADDR  = '0;
        AWVALID = 1'b0;
        WDATA   = '0;
        WSTRB   = '0;
        WVALID  = 1'b0;
        BREADY  = 1'b0;
        ARADDR  = '0;
        ARVALID = 1'b0;
        RREADY  = 1'b0;
        protocol_errors = 0;
    endtask

    // AW and W are intentionally launched together but complete independently.
    task automatic write(input logic [6:0] addr,
                         input logic [31:0] data);
        bit aw_done;
        bit w_done;

        aw_done = 1'b0;
        w_done  = 1'b0;

        @(negedge ACLK);
        AWADDR  = addr;
        AWVALID = 1'b1;
        WDATA   = data;
        WSTRB   = 4'hF;
        WVALID  = 1'b1;

        while (!aw_done || !w_done) begin
            @(posedge ACLK);
            if (AWVALID && AWREADY)
                aw_done = 1'b1;
            if (WVALID && WREADY)
                w_done = 1'b1;

            @(negedge ACLK);
            if (aw_done)
                AWVALID = 1'b0;
            if (w_done)
                WVALID = 1'b0;
        end

        BREADY = 1'b1;
        @(posedge ACLK);
        while (!BVALID)
            @(posedge ACLK);

        if (BRESP != 2'b00) begin
            protocol_errors++;
            $display("AXIL_ERROR: BRESP=%0b addr=0x%02h", BRESP, addr);
        end

        @(negedge ACLK);
        BREADY = 1'b0;
    endtask

    task automatic read(input  logic [6:0] addr,
                        output logic [31:0] data);
        @(negedge ACLK);
        ARADDR  = addr;
        ARVALID = 1'b1;
        RREADY  = 1'b1;

        @(posedge ACLK);
        while (!ARREADY)
            @(posedge ACLK);

        @(negedge ACLK);
        ARVALID = 1'b0;

        @(posedge ACLK);
        while (!RVALID)
            @(posedge ACLK);

        data = RDATA;
        if (RRESP != 2'b00) begin
            protocol_errors++;
            $display("AXIL_ERROR: RRESP=%0b addr=0x%02h", RRESP, addr);
        end

        @(negedge ACLK);
        RREADY = 1'b0;
    endtask
endinterface


interface axi_full_if(input logic ACLK);
    localparam int unsigned MEM_BYTES = 1024 * 1024;

    logic        ARESETN;

    logic [31:0] ARADDR;
    logic [7:0]  ARLEN;
    logic [2:0]  ARSIZE;
    logic [1:0]  ARBURST;
    logic        ARVALID;
    logic        ARREADY;

    logic [63:0] RDATA;
    logic [1:0]  RRESP;
    logic        RLAST;
    logic        RVALID;
    logic        RREADY;

    logic [31:0] AWADDR;
    logic [7:0]  AWLEN;
    logic [2:0]  AWSIZE;
    logic [1:0]  AWBURST;
    logic        AWVALID;
    logic        AWREADY;

    logic [63:0] WDATA;
    logic [7:0]  WSTRB;
    logic        WLAST;
    logic        WVALID;
    logic        WREADY;

    logic [1:0]  BRESP;
    logic        BVALID;
    logic        BREADY;

    // Observation-only signals connected from the integrated regulator.
    logic        rbr_r_wait;
    logic        rbr_w_wait;

    byte unsigned memory [0:MEM_BYTES-1];

    int unsigned protocol_errors;
    int unsigned wlast_errors;

    bit random_stalls;
    int unsigned ar_ready_percent;
    int unsigned r_valid_percent;
    int unsigned aw_ready_percent;
    int unsigned w_ready_percent;
    int unsigned b_valid_percent;

    task automatic set_stalls(input bit enable);
        random_stalls   = enable;
        ar_ready_percent = enable ? 70 : 100;
        r_valid_percent  = enable ? 75 : 100;
        aw_ready_percent = enable ? 70 : 100;
        w_ready_percent  = enable ? 65 : 100;
        b_valid_percent  = enable ? 70 : 100;
    endtask

    task automatic load_region(input int unsigned addr,
                               input byte unsigned data[]);
        foreach (data[i])
            memory[addr + i] = data[i];
    endtask

    task automatic fill_region(input int unsigned addr,
                               input int unsigned count,
                               input byte unsigned value);
        for (int unsigned i = 0; i < count; i++)
            memory[addr + i] = value;
    endtask

    function automatic int unsigned compare_region(
        input int unsigned addr,
        input byte unsigned data[]
    );
        int unsigned errors;

        errors = 0;
        foreach (data[i]) begin
            if (memory[addr + i] !== data[i]) begin
                if (errors < 4)
                    $display("MEM_MISMATCH: addr=0x%08h exp=%02h got=%02h",
                             addr + i, data[i], memory[addr + i]);
                errors++;
            end
        end

        return errors;
    endfunction
endinterface
