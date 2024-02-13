//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: LJQ
// Description: 测试采用随机生成输入数据，如data_in，data_insert，有效位宽，valid_in,ready_out，适配于各种总线宽度，如16/32/64等
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////


`define DATA_WIDTH 32

`define assert_header(signal, value) \
        if (signal !== value) begin \
            $display("ASSERTION INSERT HEADER FAILED "); \
            $finish; \
        end
        
`define assert_data(signal, value) \
        if (signal !== value) begin \
            $display("ASSERTION DATA FAILED "); \
            $finish; \
        end
`define assert_last(signal, value) \
        if (signal !== value) begin \
            $display("ASSERTION LAST FAILED "); \
            $finish; \
        end

module skid_sim;
  reg                                clk;
  reg                                rst_n;

  // AXI Stream input original data
  reg                                valid_in;
  reg [`DATA_WIDTH-1:0]              data_in;
  reg [(`DATA_WIDTH / 8)-1:0]        keep_in;
  reg                                last_in;
  wire                               ready_in;

  // AXI Stream output with header inserted
  wire                   valid_out;
  wire [`DATA_WIDTH-1:0]             data_out;
  wire [(`DATA_WIDTH / 8)-1:0]       keep_out;
  wire                               last_out;  
  reg                                ready_out;

  reg                                valid_insert;
  reg  [`DATA_WIDTH-1:0]             data_insert;
  reg  [(`DATA_WIDTH / 8)-1:0]       keep_insert;
  reg  [$clog2(`DATA_WIDTH / 8)-1:0] byte_insert_cnt;
  wire                               ready_insert;
  
  integer                            data_wd_index;

  axi_stream_insert_header #(
    .DATA_WD(`DATA_WIDTH)
  ) axi_stream_insert_header_inst (
    .clk(clk),
    .rst_n(rst_n),
    .ready_in(ready_in),
    .valid_in(valid_in),
    .data_in(data_in),
    .keep_in(keep_in),
    .last_in(last_in),

    .keep_out(keep_out),
    .last_out(last_out),  // Change from wire to output
    .ready_out(ready_out),
    .valid_out(valid_out),
    .data_out(data_out),

    .valid_insert(valid_insert),
    .data_insert(data_insert),  // Change from wire to output
    .keep_insert(keep_insert),
    .byte_insert_cnt(byte_insert_cnt),
    .ready_insert(ready_insert)
  );
  
        reg [31:0] cnt;
        integer reset_index;
        integer insert_index;
        integer last_index;
        integer transfer_index; 
        integer breakdown_index; 
        
        reg [`DATA_WIDTH-1:0]insert_data;
        reg [`DATA_WIDTH-1:0]first_data_in;
        wire [`DATA_WIDTH-1:0]insert_header;
        reg  [31:0] byte_index;
        wire [`DATA_WIDTH-1:0]first_data;
        wire [`DATA_WIDTH-1:0]last_data_in;
        reg first_flag,first_in;
          
        reg [`DATA_WIDTH-1:0]data_out_last;
        
        parameter CLK_PERIOD = 1; // 时钟周期为 10 个时间单位
        parameter RESET_PERIOD = 10000; // 复位周期最大值

        initial begin
                clk = 0;
                forever #(CLK_PERIOD) clk = ~clk;
        end
        

        //随机产生复位信号
        always @(posedge clk) begin
                for (reset_index = {$random($time)}%5000 ; reset_index > 0 ; reset_index = reset_index-1)begin
                    @(posedge clk);
                    rst_n = 1;
                end
                    rst_n = 0; 
        end

        // 监测时钟上升沿并在随机上升沿产生last_in脉冲
        always @(posedge clk) begin
            for (last_index = {$random($time)}%500 ; last_index > 0 ; last_index = last_index-1)begin
                @(posedge clk);
            end
            last_in <= 1;
            keep_in <= (1 << (`DATA_WIDTH / 8)) - (1 << ({$random($time+3)} % (`DATA_WIDTH / 8)));// 随机生成DATA_BYTE_WD位数，如32位的随机生成1111/1110/1100/1000
            @(posedge clk);
            last_in <= 0;
        end
          
        // 监测时钟上升沿并在随机上升沿产生valid_insert脉冲
        always @(posedge clk) begin
            for (insert_index = {$random($time)}%500 ; insert_index > 0 ; insert_index = insert_index-1)begin
                @(posedge clk);
                valid_insert <= 0;    // 随机开始插入header
            end

                valid_insert <= 1;    // 随机开始插入header

                data_insert  <= {$random($time+1)} % ((1 << `DATA_WIDTH)-1);
                byte_insert_cnt <= {$random($time+2)} % ((1 << (`DATA_WIDTH / 8))-1);//$urandom_range(0, (`DATA_WIDTH / 8));

        end
        //  first_flag用于标记每一轮数据传输，仅在testbench中用于检测仿真结果
        assign insert_header = ((insert_data & ((1 << (byte_index << 3)) - 1)) << (`DATA_WIDTH - (byte_index << 3)));
        always @(posedge clk) begin
            if (!rst_n) begin
                valid_in <= 1;
                first_flag <= 0;
                byte_index <= 0;
            end
            else begin
                if (valid_insert && ready_insert)begin
                    if(!first_flag)begin
                        first_flag <= 1;
                        byte_index <= byte_insert_cnt+1;
                        insert_data <= data_insert;
                    end
                end
                if (ready_out && valid_out)begin
                    if(last_out)begin
                        first_flag <= 0;
                    end
                end
            end
        end

        // 存储最后一个输入数据进行检测  
        assign first_data = (cnt == 1 && first_flag && first_in) ? (insert_header | ((data_in & (((1 << ((`DATA_WIDTH / 8-(byte_index)) << 3)) - 1) << ((byte_index) << 3))) >>> ((byte_index) << 3))) : first_data;
        always @(posedge clk) begin
            if (!rst_n) begin
                first_in <= 0;
            end
                if (valid_insert && ready_insert)begin
                    if(!first_flag)begin
                        data_in <= {$random($time)} % ((1 << `DATA_WIDTH)-1);
                    end
                end
                if (ready_in && valid_in)begin 
                    if(first_flag && !first_in )begin// 第一次得到数据
                        first_in <= 1;    
                    end   
//                    if (cnt == 1 && first_flag && first_in)  begin
//                        first_data_in <= data_in;
//                    end
                    data_in <= data_in + 1;
                end
                if (ready_out && valid_out)begin
                    if(last_out)begin
                        first_in <= 0;
                    end
                end
        end
        
        // valid_in的随即激励
          always @(posedge clk) begin
            if (!rst_n) begin
                valid_in <= 1;
            end
            else begin
                valid_in <= $random ;
            end
        end

        // ready_out的随即激励
          always @(posedge clk) begin
            if (!rst_n) begin
                ready_out <= 1;
            end
            else begin
                ready_out <= $random ;
            end
        end

        // 存储最后一个输入数据进行检测  
        assign last_data_in = (first_flag && last_in) ? data_in : last_data_in;
        // 
        integer index; 
        // 用于指示keep_in的有效位数
        wire [`DATA_WIDTH / 8 - 1 : 0]     onebit_count_temp;
        assign  onebit_count_temp =  count_one(keep_in);

        wire [3:0]indicate_data_out,indicate_data_out_last;
        assign indicate_data_out = (data_out & (15 << (`DATA_WIDTH - ((byte_index) << 3)))) >>> (`DATA_WIDTH - ((byte_index) << 3));
        assign indicate_data_out_last = (data_out_last & (15 << (`DATA_WIDTH - ((byte_index) << 3)))) >>> (`DATA_WIDTH - ((byte_index) << 3));

        // Display output data
        always @(posedge clk) begin
            if (!rst_n) begin
                    cnt <= 1;// 指示待发的第一个数据
                    data_out_last <= 0;
                end
            if (ready_out && valid_out)begin
                cnt <= cnt + 1;
                if(cnt==1 && first_flag)begin
                    `assert_header(data_out, first_data) // 用来检验第一个数据是否正确
                end
                else if(cnt>=3 && first_flag && !last_out) begin
                    `assert_data(indicate_data_out, indicate_data_out_last + 4'b0001)// 用来检验数据是否按序无重复无丢失发送
                end
                else if(last_out) begin
                        $display("LAST Data is: %h, header valid bit is: %h, valid byte is %h", last_data_in, byte_index, keep_in);

                        if((byte_index + onebit_count_temp)<= (`DATA_WIDTH / 8))begin
                                for (index = 0; index < (`DATA_WIDTH / 8)-byte_index; index = index + 1) begin
                                    if(keep_in[index + byte_index] == 1)begin
                                        `assert_last(data_out[((index << 3) + 7) -: 8],last_data_in[(((index + byte_index) << 3) + 7) -: 8])
                                    end
                                end
                        end
                        else begin
                                for (index = 0; index < byte_index; index = index + 1) begin
                                    if(keep_in[(byte_index - index)-1] == 1)begin
                                        `assert_last(data_out[((((`DATA_WIDTH / 8) - index - 1) << 3) + 7) -: 8],last_data_in[((((byte_index - index -1)) << 3) + 7) -: 8])
                                    end
                                end
                        end
                end
                $display("Data is: %h, is the last one ? : %h, valid byte is %h", data_out, last_out, keep_out);

                data_out_last <= data_out;
                if(last_out)cnt <= 1;
            end
        end 
        
        //           1-bit 计算模块
        function [`DATA_WIDTH / 8-1:0] count_one;
                input[`DATA_WIDTH / 8-1:0] binary_number;
              
                reg [`DATA_WIDTH / 8-1:0] xor_number;
                begin
                    xor_number = binary_number ^ {(`DATA_WIDTH / 8){1'b1}};
                    count_one = (`DATA_WIDTH / 8) - $clog2(xor_number + 1);
                end
  
        endfunction  
          
endmodule
