module axi_lite_block (input  logic ACLK, ARESET, AWVALID, WVALID, BREADY, ARVALID, RREADY, 
                       input  logic [31:0] AWADDR, WDATA, ARADDR,
                       output logic AWREADY, WREADY, BVALID, RVALID, ARREADY,
                       output logic [31:0] RDATA, output logic [1:0] RRESP, BRESP);

    logic [31:0] mem [0:31];
    logic [6:0] i;
    always_ff @(posedge ACLK or posedge ARESET) begin
        if (ARESET) begin
            AWREADY <= 0;
            WREADY  <= 0;
	    i <= 0;
	for (int i = 0; i < 32; i++) begin
                mem[i] <= 32'h0;
        end 
	end else begin
            if (AWVALID && WVALID && !AWREADY && !WREADY) begin
                AWREADY <= 1;
                WREADY  <= 1;
            end else begin
                AWREADY <= 0;
                WREADY  <= 0;
            end
        end
    end

    always_ff @(posedge ACLK or posedge ARESET) begin
        if (ARESET) begin
            BVALID <= 0;
            BRESP  <= 0;
        end else begin
            if (AWVALID && WVALID && AWREADY && WREADY) begin
                // Direct indexing using the raw address
                mem[AWADDR] <= WDATA; 
                BVALID <= 1;
                BRESP  <= 0; 
            end else if (BVALID && BREADY) begin
                BVALID <= 0;
            end
        end
    end

    always_ff @(posedge ACLK or posedge ARESET) begin
        if (ARESET) begin
            ARREADY <= 0;
        end else begin
            if (ARVALID && !ARREADY) begin
                ARREADY <= 1;
            end else begin
                ARREADY <= 0;
            end
        end
    end

    always_ff @(posedge ACLK or posedge ARESET) begin
        if (ARESET) begin
            RVALID <= 0;
            RRESP  <= 0;
            RDATA  <= 0;
        end else begin
            if (ARVALID && ARREADY && !RVALID) begin
                // Direct indexing using the raw address
                RDATA  <= mem[ARADDR]; 
                RVALID <= 1;
                RRESP  <= 0; 
            end else if (RVALID && RREADY) begin
                RVALID <= 0;
            end
        end
    end

endmodule
