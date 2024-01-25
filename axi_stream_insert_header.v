`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: LJQ
// 
// Create Date: 2024/01/24 13:49:19
// Design Name: 
// Module Name: axi_stream_insert_header
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 将输入的header头部去除无效字节，与有效数据进行拼接重组后按照AXI STREAM输出
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ns

module axi_stream_insert_header #(
    parameter                      DATA_WD = 32,
    parameter                      DATA_BYTE_WD = DATA_WD / 8,
    parameter                      BYTE_CNT_WD = $clog2(DATA_BYTE_WD)
	) (
	input 				            clk 	,//时钟信号   
	input 				            rst_n	,//复位信号

    // AXI Stream input original data
    input                           valid_in,
    input  [DATA_WD-1 : 0]          data_in,
    input  [DATA_BYTE_WD-1 : 0]     keep_in,
    input                           last_in,
    output                          ready_in,
    // AXI Stream output with header inserted
    output                          valid_out,
    output   [DATA_WD-1 : 0]        data_out,
    output reg [DATA_BYTE_WD-1 : 0] keep_out,
    output reg                      last_out,
    input                           ready_out,
    // The header to be inserted to AXI Stream input
    input                           valid_insert,
    input [DATA_WD-1 : 0]           data_insert,
    input [DATA_BYTE_WD-1 : 0]      keep_insert,
    input [BYTE_CNT_WD-1 : 0]       byte_insert_cnt,
    output  reg                     ready_insert 
);

          // signals 
         reg                  buf_valid; // 指示缓存有数据
         reg  [DATA_WD-1:0]   buf_data;  // 用于数据暂存

         wire [DATA_WD-1:0]   concatenated_data;  // 用于数据重组
         
         reg [DATA_WD-1:0]   data_reg_last = 0;
         reg [DATA_WD-1:0]   data_reg = 0;
         reg last_out_store = 0;
         reg [DATA_BYTE_WD-1 : 0] keep_out_store = 0;
         reg start_en;
         reg start_data;
         wire [BYTE_CNT_WD-1 : 0] ones_count_temp;
         reg first = 0;
         integer byte_index_i,byte_index_j;
         
         wire [BYTE_CNT_WD : 0]   byte_cnt; // 表示keep_insert 1的个数，e.g. keep_insert（1110）--> byte_cnt(2)
        
         always @ (posedge clk or negedge rst_n) begin
             if(!rst_n) begin
                 ready_insert <= 1;//有个buf因此复位后至少可以收一个数据
                 start_en <= 0;
             end
             else if(!start_en)
                 ready_insert <= 1;
             else if(valid_insert) // 已经传来过了一个header数据
                 ready_insert <= 0; 
         end
        
        initial  buf_valid = 0;
		always @(posedge clk)
		if (!rst_n)
			buf_valid <= 0;
		else if ((valid_in && ready_in) && (valid_out && !ready_out) && start_en)
			buf_valid <= 1;
		else if (ready_out)
			buf_valid <= 0;
        

         
         always @ (posedge clk or negedge rst_n ) begin
             if(!rst_n) //可能有些控制信号通过本模块的data端口进行传输，因此有必要进行复位。
                begin
                     buf_data <= 0;
                end
             else if(!ready_out && (valid_in && ready_in)) // 当接收握手并且可以暂存时，更新buffer
                 buf_data <=  start_en ? data_in : 0;
         end
         
         // 用于数据表示和交互
         wire [DATA_WD-1:0]   data_temp;
         wire [DATA_WD-1:0]   data_temp_last;
         reg [DATA_WD-1:0]    data_temp_store;
         
         always @ (posedge clk or negedge rst_n) begin
         if(!rst_n) begin
                data_temp_store <= 0;
         end
         else begin
                data_temp_store <= data_temp ;
             end
         end
         
         assign     concatenated_data = ((data_temp_last & ((1 << (8 * (byte_cnt))) - 1)) << (DATA_WD-8 * (byte_cnt))) | 
                                        (data_temp & ((1 << (8 * (DATA_BYTE_WD-byte_cnt))) - 1) << (8 * (byte_cnt)));  // 位拼接逻辑

         // 只有在接收到header后才有效
         assign ready_in = (start_en) ? (last_out ? 0 : !buf_valid) : 0;
         assign	valid_out  =   start_en ? (rst_n && (valid_in || buf_valid)): 0;
         
         assign data_temp  =  start_en ? (last_out_store ? data_reg_last : ((first ? ((ready_out &&valid_out)? (buf_valid ? buf_data : data_in ) : data_temp): data_reg ))) : 0;
         assign data_temp_last = start_en ? ((ready_out && valid_out) ? data_temp_store : data_temp_last): 0;
         // 判断逻辑 ：         接收到header表示准备数据的传输start_en有效，否则data_temp为0-->
         // 若接收到的不是最后一拍数据，则进行第一拍数据的判断,否则data_temp为最后一拍数据-->
         // 如果已经接收到了第一拍数据，则进行buffer判断，查看数据是否在buffer中，否则data_temp为header数据
         // 由于数据需要重组拼接，需要在输出方未握手下保留前一拍数据，故进行握手判断
         assign data_out   = concatenated_data ; 
         assign ones_count_temp = count_one(keep_out_store);// 计算1的位数，通过线网连接即时更新

        always @ (posedge clk or negedge rst_n) begin
             if(!rst_n) begin
                     last_out <= 0;
                     keep_out <= 4'b1111;
             end
             else begin
                     if(last_out_store && (ready_out && valid_out)) begin
                        if((keep_out_store + byte_cnt) < keep_out_store)begin  // 若满足此条件，说明最后一个数据的keep_in和插入header的keep_insert的1bit的总和大于DATA_BYTE_WD，总发送data数比发送方的data_in多1
                            last_out <= 1;
                            keep_out <= ((1 << (ones_count_temp + byte_cnt - DATA_BYTE_WD))-1) << (DATA_BYTE_WD-(ones_count_temp + byte_cnt - DATA_BYTE_WD));
                            first <= 0;
                        end
                        else begin
                            last_out <= 1;
                            keep_out <= ((1 << (ones_count_temp + byte_cnt))-1) << (DATA_BYTE_WD-(ones_count_temp + byte_cnt));
                            first <= 0;
                        end

                         if(last_out && (ready_out && valid_out)) begin
                            last_out <= 0;
                            last_out_store <= 0;
                            start_en <= 0;
                         end         
                     end
             end
         end
        
        
         always @(posedge last_in or negedge rst_n) begin
                if(!rst_n) begin
                     data_reg_last <= 0; // 寄存最后一个数据
                end
                if(last_in && start_en) begin    // 接收到最后一个数据        
                        for (byte_index_i = 0; byte_index_i < DATA_BYTE_WD; byte_index_i = byte_index_i + 1) begin
                            data_reg_last[((byte_index_i) * 8 + 7) -: 8] <= (keep_in[byte_index_i] == 1) ? data_temp[(byte_index_i * 8 + 7) -: 8] : 8'b0;
                        end
                            last_out_store <= 1;
                            keep_out_store <= keep_in;          
                end
           end
           
          assign byte_cnt =  byte_insert_cnt + 1;
          
         always @(posedge clk or negedge rst_n) begin
            if(!rst_n) begin
                data_reg   <=   0;
                start_en   <=   1'b0;
             end
            if(!start_en && (valid_insert && ready_insert))begin // 还未开始传header并且插入握手成功
                data_reg   <=   data_insert;
                start_en   <=   1'b1;
            end

         end
         
          always @(*) begin
            if(!rst_n) begin
                first <= 0;
                start_data <= 0;
             end
            if(!first && (valid_in && ready_in))begin // 第一次得到数据
                first <= 1;              
            end
            if(first && (valid_out && ready_out))begin
                start_data <= 1;
            end
         end

          // 1-bit 计算模块
          function [BYTE_CNT_WD-1:0] count_one;
                input[DATA_BYTE_WD-1:0] binary_number;
              
                reg [BYTE_CNT_WD-1:0] CNT ;
                begin
                 for ( CNT = 0; binary_number ; CNT = CNT + 1) begin
                      binary_number = binary_number & (binary_number-1);
                 end
                 count_one = CNT;
                end
            endfunction
    
endmodule
