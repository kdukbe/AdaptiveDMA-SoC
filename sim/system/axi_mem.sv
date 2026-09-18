`timescale 1ns/1ps

module axi_mem(axi_full_if bus);

    typedef struct packed {
        logic [31:0] addr;
        logic [7:0]  len;
    } req_t;

    req_t r_queue[$];
    req_t w_queue[$];
    req_t r_popped_req;
    req_t w_popped_req;
    req_t r_push_req;
    req_t w_push_req;

    logic        ar_gate;
    logic        r_gate;
    logic        aw_gate;
    logic        w_gate;
    logic        b_gate;

    logic        r_active;
    logic [31:0] r_addr;
    logic [7:0]  r_len;
    logic [7:0]  r_beat;

    logic        rvalid_reg;
    logic [63:0] rdata_reg;
    logic        rlast_reg;

    logic [7:0]  w_beat;
    logic [7:0]  w_check_len;
    integer      w_count;
    integer      b_pending;
    logic        bvalid_reg;

    int unsigned accepted_reads;
    int unsigned accepted_writes;

    wire ar_hs = bus.ARVALID && bus.ARREADY;
    wire r_hs  = bus.RVALID  && bus.RREADY;
    wire aw_hs = bus.AWVALID && bus.AWREADY;
    wire w_hs  = bus.WVALID  && bus.WREADY;
    wire b_hs  = bus.BVALID  && bus.BREADY;

    assign bus.ARREADY = bus.ARESETN && (r_queue.size() < 64) && ar_gate;
    assign bus.AWREADY = bus.ARESETN && (w_queue.size() < 64) && aw_gate;
    assign bus.WREADY  = bus.ARESETN && (w_count != 0) && w_gate;

    assign bus.RVALID = rvalid_reg;
    assign bus.RDATA  = rdata_reg;
    assign bus.RLAST  = rlast_reg;
    assign bus.RRESP  = 2'b00;

    assign bus.BVALID = bvalid_reg;
    assign bus.BRESP  = 2'b00;

    function automatic logic [63:0] read_word(input logic [31:0] addr);
        logic [63:0] value;
        int unsigned k;
        begin
            value = 64'd0;
            for (k = 0; k < 8; k++) begin
                if ((addr + k) < bus.MEM_BYTES)
                    value[k*8 +: 8] = bus.memory[addr + k];
            end
            return value;
        end
    endfunction

    // READY may change at any time. VALID gates are sampled only while the
    // corresponding registered VALID is low, so payload stays stable on stall.
    always @(posedge bus.ACLK) begin
        if (!bus.ARESETN) begin
            ar_gate <= 1'b0;
            r_gate  <= 1'b0;
            aw_gate <= 1'b0;
            w_gate  <= 1'b0;
            b_gate  <= 1'b0;
        end else begin
            ar_gate <= ($urandom_range(100, 1) <= bus.ar_ready_percent);
            r_gate  <= ($urandom_range(100, 1) <= bus.r_valid_percent);
            aw_gate <= ($urandom_range(100, 1) <= bus.aw_ready_percent);
            w_gate  <= ($urandom_range(100, 1) <= bus.w_ready_percent);
            b_gate  <= ($urandom_range(100, 1) <= bus.b_valid_percent);
        end
    end

    // Read address queue and ordered read-data response.
    always @(posedge bus.ACLK) begin
        if (!bus.ARESETN) begin
            r_queue.delete();
            r_active      <= 1'b0;
            r_addr        <= 32'd0;
            r_len         <= 8'd0;
            r_beat        <= 8'd0;
            rvalid_reg    <= 1'b0;
            rdata_reg     <= 64'd0;
            rlast_reg     <= 1'b0;
            accepted_reads <= 0;
        end else begin
            if (ar_hs) begin
                r_push_req.addr = bus.ARADDR;
                r_push_req.len  = bus.ARLEN;
                r_queue.push_back(r_push_req);
                accepted_reads <= accepted_reads + 1;
            end

            if (!r_active && (r_queue.size() != 0)) begin
                r_popped_req = r_queue.pop_front();
                r_active <= 1'b1;
                r_addr   <= r_popped_req.addr;
                r_len    <= r_popped_req.len;
                r_beat   <= 8'd0;
            end

            if (rvalid_reg) begin
                if (bus.RREADY) begin
                    if (rlast_reg) begin
                        rvalid_reg <= 1'b0;
                        rlast_reg  <= 1'b0;
                        r_active   <= 1'b0;
                    end else begin
                        r_beat    <= r_beat + 1'b1;
                        rdata_reg <= read_word(r_addr + ((r_beat + 1'b1) << 3));
                        rlast_reg <= ((r_beat + 1'b1) == r_len);
                        if (!r_gate)
                            rvalid_reg <= 1'b0;
                    end
                end
            end else if (r_active && r_gate) begin
                rvalid_reg <= 1'b1;
                rdata_reg  <= read_word(r_addr + (r_beat << 3));
                rlast_reg  <= (r_beat == r_len);
            end
        end
    end

    // Write address queue and byte-addressed memory update.
    always @(posedge bus.ACLK) begin : write_model
        int unsigned k;

        if (!bus.ARESETN) begin
            w_queue.delete();
            w_beat          <= 8'd0;
            w_check_len     <= 8'd0;
            bus.wlast_errors <= 0;
            w_count         <= 0;
            accepted_writes <= 0;
        end else begin
            if (aw_hs) begin
                w_push_req.addr = bus.AWADDR;
                w_push_req.len  = bus.AWLEN;
                w_queue.push_back(w_push_req);
                accepted_writes <= accepted_writes + 1;
            end

            if (w_hs) begin
                if (w_beat == 0) begin
                    w_check_len <= w_queue[0].len;
                    if (bus.WLAST != (w_queue[0].len == 0)) begin
                        bus.wlast_errors <= bus.wlast_errors + 1;
                        $display("AXI_ERROR: incorrect WLAST at %0t", $time);
                    end
                end else if (bus.WLAST != (w_beat == w_check_len)) begin
                    bus.wlast_errors <= bus.wlast_errors + 1;
                    $display("AXI_ERROR: incorrect WLAST at %0t", $time);
                end

                for (k = 0; k < 8; k++) begin
                    if (bus.WSTRB[k] &&
                        ((w_queue[0].addr + (w_beat << 3) + k) < bus.MEM_BYTES))
                        bus.memory[w_queue[0].addr + (w_beat << 3) + k]
                            <= bus.WDATA[k*8 +: 8];
                end

                if (bus.WLAST) begin
                    w_popped_req = w_queue.pop_front();
                    w_beat <= 8'd0;
                end else begin
                    w_beat <= w_beat + 1'b1;
                end
            end

            case ({aw_hs, w_hs && bus.WLAST})
                2'b10: w_count <= w_count + 1;
                2'b01: w_count <= w_count - 1;
                default: w_count <= w_count;
            endcase
        end
    end

    // One B response is generated for every accepted WLAST.
    always @(posedge bus.ACLK) begin
        if (!bus.ARESETN) begin
            b_pending  <= 0;
            bvalid_reg <= 1'b0;
        end else begin
            case ({w_hs && bus.WLAST, b_hs})
                2'b10: b_pending <= b_pending + 1;
                2'b01: b_pending <= b_pending - 1;
                default: b_pending <= b_pending;
            endcase

            if (bvalid_reg) begin
                if (bus.BREADY)
                    bvalid_reg <= 1'b0;
            end else if ((b_pending != 0) && b_gate) begin
                bvalid_reg <= 1'b1;
            end
        end
    end

    // Checks performed by the slave model itself.
    always @(posedge bus.ACLK) begin
        if (!bus.ARESETN) begin
            bus.protocol_errors <= 0;
        end else begin
            if (ar_hs) begin
                if ((bus.ARLEN > 8'd15) || (bus.ARSIZE != 3'd3) ||
                    (bus.ARBURST != 2'b01)) begin
                    bus.protocol_errors <= bus.protocol_errors + 1;
                    $display("AXI_ERROR: invalid AR attributes at %0t", $time);
                end
                if ({1'b0, bus.ARADDR[11:0]} +
                    (({5'd0, bus.ARLEN} + 13'd1) << 3) > 13'd4096) begin
                    bus.protocol_errors <= bus.protocol_errors + 1;
                    $display("AXI_ERROR: AR crosses 4KB at %0t", $time);
                end
            end

            if (aw_hs) begin
                if ((bus.AWLEN > 8'd15) || (bus.AWSIZE != 3'd3) ||
                    (bus.AWBURST != 2'b01)) begin
                    bus.protocol_errors <= bus.protocol_errors + 1;
                    $display("AXI_ERROR: invalid AW attributes at %0t", $time);
                end
                if ({1'b0, bus.AWADDR[11:0]} +
                    (({5'd0, bus.AWLEN} + 13'd1) << 3) > 13'd4096) begin
                    bus.protocol_errors <= bus.protocol_errors + 1;
                    $display("AXI_ERROR: AW crosses 4KB at %0t", $time);
                end
            end

        end
    end

endmodule
