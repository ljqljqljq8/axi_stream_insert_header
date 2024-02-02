//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: LJQ
// Description: 测试采用随机生成输入数据，如data_in，data_insert，有效位宽，valid_in,ready_out，适配于各种总线宽度，如16/32/64等
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

`define DATA_WIDTH 32

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
  
        reg [9:0] cnt;
        integer insert_index;

        initial begin
                clk = 0;
                forever #2 clk = ~clk;
        end

//         Reset and initialization
        initial begin
  
                rst_n = 0;
                valid_in = 1;
                data_in = {$random($time)} % ((1 << `DATA_WIDTH)-1);
                last_in = 0;
            
                ready_out = 0;
            
                valid_insert = 0;
                data_insert = 0;
                keep_insert = 0;
                byte_insert_cnt = 0;
            
                #10 rst_n = 1;
                data_insert = {$random($time+1)} % ((1 << `DATA_WIDTH)-1);
                byte_insert_cnt = {$random($time+2)} % ((1 << (`DATA_WIDTH / 8))-1);//$urandom_range(0, (`DATA_WIDTH / 8));
                
                for (insert_index = {$random($time)}%20 ; insert_index > 0 ; insert_index = insert_index-1)begin
                    valid_insert <= 0;    // 随机开始插入header
                    @(posedge clk);
                end
                valid_insert = 1;
        end
        
         // Input data generation
        always @(posedge clk) begin
                if (!rst_n) begin
                    cnt <= 0;
                    last_in <= 0;
                    keep_in <= 0;
                end
                else begin
                    if (ready_in && valid_in)
                        data_in <= data_in + 1;
                    else begin
                        data_in <= data_in;
                        end
                    cnt <= cnt + 1;
                    
                                if (cnt % 75 == 0 && cnt) begin
                                    last_in <= 1;
                                    keep_in <= (1 << (`DATA_WIDTH / 8)) - (1 << ({$random($time+3)} % (`DATA_WIDTH / 8)));// 随机生成DATA_BYTE_WD位数，如32位的随机生成1111/1110/1100/1000
/*                        极端情况：当last_in有效，即输入最后一个数据时，ready_out长期无效，是否能够有效接收到最后一个数据                          
                                    for (breakdown_index = 16 ; breakdown_index > 0 ; breakdown_index = breakdown_index-1)begin
                                    ready_out <= 0;    // 随机崩溃周期
                                    @(posedge clk);
                                    end
                                    ready_out <= 1;                                                                                     */

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
        
        // Display output data
        always @(posedge clk) begin
            if (ready_out && valid_out)
            $display("Data is: %h, is the last one ? : %h, valid byte is %h", data_out, last_out, keep_out);
        end 
          
          
endmodule
