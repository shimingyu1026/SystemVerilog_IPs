module single_port_register #(
    parameter int WIDTH      = 32,
    parameter int DEPTH      = 1024,
    parameter int ADDR_WIDTH = $clog2(DEPTH) 
)(
    input  logic                    clk,
    input  logic                    en,
    input  logic [3:0]              we,
    input  logic [ADDR_WIDTH-1:0]   addr,
    input  logic [WIDTH-1:0]        din,
    output logic [WIDTH-1:0]        dout
);

    // 定义存储器数组
    logic [WIDTH-1:0] ram [0:DEPTH-1];

    always_ff @(posedge clk) begin
        if (en) begin
            unique case (we)
                4'hf: ram[addr] <= din;
                4'h7: ram[addr] <= {ram[addr][31:24], din[23:0]};
                4'h3: ram[addr] <= {ram[addr][31:16], din[15:0]};
                4'h1: ram[addr] <= {ram[addr][31:8],  din[7:0]};
                default: ram[addr] <= '0;
            endcase
        end else begin
            dout <= ram[addr];
        end
    end

endmodule
