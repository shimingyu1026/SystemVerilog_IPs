`timescale 1ns / 1ps

module tb_bf16_adder;

    logic clk;
    logic rst_n;
    logic valid_in;
    logic [15:0] a, b;
    logic valid_out;
    logic [15:0] result;

    bf16_adder_pipeline dut (.*);

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // 转换函数：bf16 转 real
    // bf16 格式: 1 bit sign, 8 bits exponent (bias 127), 7 bits mantissa
    function real bf16_to_real(logic [15:0] val);
        logic sign;
        logic [7:0] exp;
        logic [6:0] mant;
        real res;
        int exp_int;
        
        sign = val[15];
        exp = val[14:7];
        mant = val[6:0];
        
        if (exp == 0) begin
            // 非规格化数或零
            res = 0.0;
        end else begin
            exp_int = int'(exp) - 127;
            res = (1.0 + real'(mant) / 128.0) * (2.0 ** real'(exp_int));
        end
        
        return sign ? -res : res;
    endfunction

    // 辅助函数：real 转 bf16 (用于生成期望值)
    function logic [15:0] real_to_bf16(real val);
        logic [15:0] res;
        logic sign;
        int exp_int;
        logic [7:0] exp;
        logic [6:0] mant;
        real mant_val;
        
        if (val == 0.0) begin
            return 16'h0000;
        end
        
        sign = (val < 0) ? 1'b1 : 1'b0;
        if (sign) val = -val;
        
        // 计算指数
        exp_int = $rtoi($log10(val) / $log10(2.0));
        if (val < 1.0) exp_int = exp_int - 1;
        exp = 8'(exp_int + 127);
        
        // 计算尾数
        mant_val = val / (2.0 ** real'(exp_int));
        mant_val = mant_val - 1.0;
        mant = 7'($rtoi(mant_val * 128.0));
        
        res = {sign, exp, mant};
        return res;
    endfunction

    initial begin
        rst_n = 0;
        valid_in = 0;
        a = 0; 
        b = 0;
        #20;
        rst_n = 1;
        #10;

        // Test Case 1: 1.0 + 2.0 = 3.0
        // 1.0 = 0x3F80, 2.0 = 0x4000, 期望结果 3.0 = 0x4040
        @(posedge clk);
        valid_in = 1; 
        a = 16'h3F80; 
        b = 16'h4000;
        @(posedge clk);
        valid_in = 0;
        
        // 等待流水线完成 (4个周期: STAGE1 -> STAGE2 -> STAGE3 -> DONE)
        repeat(4) @(posedge clk);
        
        // Test Case 2: 1.5 + 1.5 = 3.0
        // 1.5 = 0x3FC0
        @(posedge clk);
        valid_in = 1; 
        a = 16'h3FC0; 
        b = 16'h3FC0;
        @(posedge clk);
        valid_in = 0;
        repeat(4) @(posedge clk);

        // Test Case 3: 2.0 - 1.0 = 1.0 (Subtraction)
        // 2.0 = 0x4000, -1.0 = 0xBF80, 期望结果 1.0 = 0x3F80
        @(posedge clk);
        valid_in = 1; 
        a = 16'h4000; 
        b = 16'hBF80;
        @(posedge clk);
        valid_in = 0;
        repeat(4) @(posedge clk);

        // Test Case 4: Small number addition (Testing Alignment)
        // 1.0 + 0.0078125 (1/128) ≈ 1.0078125
        @(posedge clk);
        valid_in = 1; 
        a = 16'h3F80; 
        b = 16'h3C00;
        @(posedge clk);
        valid_in = 0;
        repeat(4) @(posedge clk);

        // Test Case 5: 0.5 + 0.5 = 1.0
        @(posedge clk);
        valid_in = 1;
        a = 16'h3F00;
        b = 16'h3F00;
        @(posedge clk);
        valid_in = 0;
        repeat(4) @(posedge clk);

        // Test Case 6: 0.0 + 1.0 = 1.0
        @(posedge clk);
        valid_in = 1;
        a = 16'h0000;
        b = 16'h3F80;
        @(posedge clk);
        valid_in = 0;
        repeat(4) @(posedge clk);

        #50;
        $display("=== Test Complete ===");
        $finish;
    end

    // 监控输出结果
    always @(posedge clk) begin
        if (valid_out) begin
            real result_real = bf16_to_real(result);
            $display("Time: %0t | Result Hex: 0x%04h | Real: %f", $time, result, result_real);
        end
    end

endmodule
