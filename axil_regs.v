`timescale 1ns / 1ps

module axil_regs (
    input  wire         aclk,
    input  wire         aresetn,
    input  wire [4:0]   s_axi_awaddr,
    input  wire [2:0]   s_axi_awprot,
    input  wire         s_axi_awvalid,
    output wire         s_axi_awready,
    input  wire [31:0]  s_axi_wdata,
    input  wire [3:0]   s_axi_wstrb,
    input  wire         s_axi_wvalid,
    output wire         s_axi_wready,
    output wire [1:0]   s_axi_bresp,
    output reg          s_axi_bvalid,
    input  wire         s_axi_bready,
    input  wire [4:0]   s_axi_araddr,
    input  wire [2:0]   s_axi_arprot,
    input  wire         s_axi_arvalid,
    output wire         s_axi_arready,
    output reg  [31:0]  s_axi_rdata,
    output wire [1:0]   s_axi_rresp,
    output reg          s_axi_rvalid,
    input  wire         s_axi_rready,
    output wire [255:0] regs_out,
    input  wire [255:0] regs_in
);

    reg [255:0] registers;
    reg [4:0]   awaddr_hold;
    reg         aw_pending;
    reg [31:0]  wdata_hold;
    reg [3:0]   wstrb_hold;
    reg         w_pending;
    integer i;

    assign regs_out = registers;
    assign s_axi_bresp = 2'b00; // OKAY
    assign s_axi_rresp = 2'b00; // OKAY

    // AW and W are independent AXI4-Lite channels.
    assign s_axi_awready = aresetn && !aw_pending && !s_axi_bvalid;
    assign s_axi_wready  = aresetn && !w_pending  && !s_axi_bvalid;
    assign s_axi_arready = aresetn && !s_axi_rvalid;

    always @(posedge aclk) begin
        if (!aresetn) begin
            registers   <= 256'b0;
            awaddr_hold <= 5'b0;
            aw_pending  <= 1'b0;
            wdata_hold  <= 32'b0;
            wstrb_hold  <= 4'b0;
            w_pending   <= 1'b0;
            s_axi_bvalid <= 1'b0;
            s_axi_rvalid <= 1'b0;
            s_axi_rdata  <= 32'b0;
        end else begin
            if (s_axi_awvalid && s_axi_awready) begin
                awaddr_hold <= s_axi_awaddr;
                aw_pending  <= 1'b1;
            end
            if (s_axi_wvalid && s_axi_wready) begin
                wdata_hold <= s_axi_wdata;
                wstrb_hold <= s_axi_wstrb;
                w_pending  <= 1'b1;
            end

            // Once both halves have arrived, commit the byte-enabled write.
            if (aw_pending && w_pending && !s_axi_bvalid) begin
                for (i = 0; i < 4; i = i + 1) begin
                    if (wstrb_hold[i])
                        registers[32*awaddr_hold[4:2] + 8*i +: 8]
                            <= wdata_hold[8*i +: 8];
                end
                aw_pending   <= 1'b0;
                w_pending    <= 1'b0;
                s_axi_bvalid <= 1'b1;
            end else if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
            end

            // Hold read data and RVALID until the master accepts them.
            if (s_axi_arvalid && s_axi_arready) begin
                s_axi_rdata  <= regs_in[32*s_axi_araddr[4:2] +: 32];
                s_axi_rvalid <= 1'b1;
            end else if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
            end
        end
    end

    // Protection inputs are intentionally unused for this register bank.
endmodule

