module bf16_adder_pipeline(
    input  logic        clk,
    input  logic        rst_n,
    input  logic        valid_in,
    input  logic [15:0] a,
    input  logic [15:0] b,
    output logic        valid_out,
    output logic        busy,
    output logic [15:0] result
);

    typedef struct packed {
        logic       sign;
        logic [7:0] exp;
        logic [6:0] mant;
    } bf16_t;
    
    localparam int MAN_WIDTH = 8;     // 1.xxxxxxx mantissa width
    localparam int CALC_WIDTH = 14;   // 足够容纳移位和精度计算 width
    
    bf16_t u_a, u_b;


    //--------------------------------
    // 状态机
    //--------------------------------
    enum logic [2:0] {
        IDLE,
        STAGE1,
        STAGE2,
        STAGE3,
        DONE
    } state, next_state;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
        end else begin
            state <= next_state;
        end
    end

    always_comb begin
        next_state = state;
        case (state)
            IDLE: begin
                if (valid_in) begin
                    next_state = STAGE1;
                end
            end
            STAGE1: next_state = STAGE2;
            STAGE2: next_state = STAGE3;
            STAGE3: next_state = DONE;
            DONE: next_state = IDLE;
        endcase
    end

    //--------------------------------
    // 输入寄存
    //--------------------------------
    logic [15:0] reg_a, reg_b;
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            reg_a <= 0;
            reg_b <= 0;
        end else if (state == IDLE && valid_in) begin
            reg_a <= a;
            reg_b <= b;
        end else begin
            reg_a <= reg_a;
            reg_b <= reg_b;
        end
    end
    assign u_a = reg_a;
    assign u_b = reg_b;
    //--------------------------------
    // STAGE1 处理
    //--------------------------------
    logic       s1_sign_res, s1_sign_res_next; // 结果符号
    logic [7:0] s1_exp_base, s1_exp_base_next; // 较大的指数
    logic       s1_is_sub, s1_is_sub_next;     // 是否是减法操作
    logic [CALC_WIDTH-1:0] s1_man_a, s1_man_a_next; // 对齐后的 A (较大的数)
    logic [CALC_WIDTH-1:0] s1_man_b, s1_man_b_next; // 对齐后的 B (较小的数)

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            s1_sign_res <= 0;
            s1_exp_base <= 0;
            s1_is_sub <= 0;
            s1_man_a <= 0;
            s1_man_b <= 0;
        end else begin
            s1_sign_res <= s1_sign_res_next;
            s1_exp_base <= s1_exp_base_next;
            s1_is_sub <= s1_is_sub_next;
            s1_man_a <= s1_man_a_next;
            s1_man_b <= s1_man_b_next;
        end
    end

    always_comb begin
        s1_sign_res_next = s1_sign_res;
        s1_exp_base_next = s1_exp_base;
        s1_is_sub_next = s1_is_sub;
        s1_man_a_next = s1_man_a;
        s1_man_b_next = s1_man_b;

        if (state == STAGE1) begin
            logic [MAN_WIDTH-1:0] man_a_raw, man_b_raw;
            logic [7:0] exp_a, exp_b;
            logic a_is_lager;
            logic [7:0] exp_diff;

            man_a_raw = (|u_a.exp) ? {1'b1, u_a.mant} : 8'b0;
            man_b_raw = (|u_b.exp) ? {1'b1, u_b.mant} : 8'b0;

            exp_a = u_a.exp;
            exp_b = u_b.exp;

            if (exp_a > exp_b) begin
                a_is_lager = 1;
            end else if (exp_a < exp_b) begin
                a_is_lager = 0;
            end else begin
                a_is_lager = (man_a_raw > man_b_raw);
            end

            if (a_is_lager) begin
                s1_sign_res_next = u_a.sign;
                s1_exp_base_next = exp_a;
                s1_is_sub_next = (u_a.sign ^ u_b.sign);

                exp_diff = exp_a - exp_b;

                s1_man_a_next = {man_a_raw, {(CALC_WIDTH-MAN_WIDTH){1'b0}}};
                s1_man_b_next = {man_b_raw, {(CALC_WIDTH-MAN_WIDTH){1'b0}}} >> exp_diff;
            end else begin
                s1_sign_res_next = u_b.sign;
                s1_exp_base_next = exp_b;
                s1_is_sub_next = (u_a.sign ^ u_b.sign);

                exp_diff = exp_b - exp_a;

                s1_man_a_next = {man_b_raw, {(CALC_WIDTH-MAN_WIDTH){1'b0}}};
                s1_man_b_next = exp_diff > CALC_WIDTH ? 0 : {man_a_raw, {(CALC_WIDTH-MAN_WIDTH){1'b0}}} >> exp_diff;
            end
        end
    end

    //--------------------------------
    // STAGE2 处理
    //--------------------------------
    logic       s2_sign_res, s2_sign_res_next; // 结果符号
    logic [7:0] s2_exp_base, s2_exp_base_next;
    logic [CALC_WIDTH:0] s2_sum, s2_sum_next; // 多 1 bit 用于溢出 (Carry)

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            s2_sign_res <= 0;
            s2_exp_base <= 0;
            s2_sum <= 0;
        end else begin
            s2_sign_res <= s2_sign_res_next;
            s2_exp_base <= s2_exp_base_next;
            s2_sum <= s2_sum_next;
        end
    end

    always_comb begin
        s2_sign_res_next = s2_sign_res;
        s2_exp_base_next = s2_exp_base;
        s2_sum_next = s2_sum;

        if (state == STAGE2) begin
            s2_sign_res_next = s1_sign_res;
            s2_exp_base_next = s1_exp_base;
            if (s1_is_sub) begin
                s2_sum_next = s1_man_a - s1_man_b;
            end else begin
                s2_sum_next = s1_man_a + s1_man_b;
            end
        end
    end

    //--------------------------------
    // STAGE3 处理
    //--------------------------------
    function automatic logic [3:0] count_leading_zeros(logic [CALC_WIDTH:0] val);
        int i;
        for (i = CALC_WIDTH; i >= 0; i--) begin
            if (val[i]) return (CALC_WIDTH - i);
        end
        return CALC_WIDTH + 1; // 全0
    endfunction

    logic [15:0] s3_result, s3_result_next;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            s3_result <= 0;
        end else begin
            s3_result <= s3_result_next;
        end
    end

    always_comb begin
        s3_result_next = s3_result;

        if (state == STAGE3) begin
            logic [3:0] llz;
            logic [7:0] final_exp;
            logic [CALC_WIDTH:0] norm_man;
            logic [6:0] final_man;
            logic round_bit;

            // 检查加法溢出
            if (s2_sum[CALC_WIDTH]) begin
                norm_man = s2_sum >> 1;
                final_exp = s2_exp_base + 1;
            end else begin
                llz = count_leading_zeros(s2_sum);

                // 结果为0
                if (s2_sum == 0) begin
                    final_exp = 0;
                    norm_man = 0;
                end else if (llz == 1) begin
                    final_exp = s2_exp_base;
                    norm_man = s2_sum;
                end else begin
                    if (llz > s2_exp_base) begin
                        //直接变成 0  FTZ
                        final_exp = 0;
                        norm_man = 0;
                    end else begin
                        norm_man = s2_sum << (llz - 1);
                        final_exp = s2_exp_base - llz + 1;
                    end
                end
            end

            final_man = norm_man[12:6];
            round_bit = norm_man[5];

            if (round_bit) begin
                if (&final_man) begin
                    final_man = 0;
                    final_exp = final_exp + 1;
                end else begin
                    final_man = final_man + 1;
                end
            end

            if (final_exp >= 255) begin
              s3_result_next = {s2_sign_res, 8'hFF, 7'b0};
            end else begin
              s3_result_next = {s2_sign_res, final_exp, final_man};
            end
        end
    end

    //--------------------------------
    // 输出
    //--------------------------------
    assign result = s3_result;
    assign valid_out = (state == DONE);
    assign busy = (state != IDLE);
endmodule
