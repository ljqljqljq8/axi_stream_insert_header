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
/*
                    Input                                   Output
                    -----                                   ------
                              --------------------------
                    ready <--|                          |<-- ready
                    valid -->|                          |--> valid
                    data  -->|    internal buffer       |--> data
                              --------------------------
*/
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
    input    [DATA_WD-1 : 0]        data_in,
    input    [DATA_BYTE_WD-1 : 0]   keep_in,
    input                           last_in,
    output                          ready_in,
    // AXI Stream output with header inserted
    output                          valid_out,
    output   [DATA_WD-1 : 0]        data_out,
    output   [DATA_BYTE_WD-1 : 0]   keep_out,
    output                          last_out,
    input                           ready_out,
    // The header to be inserted to AXI Stream input
    input                           valid_insert,
    input    [DATA_WD-1 : 0]        data_insert,
    input    [DATA_BYTE_WD-1 : 0]   keep_insert,
    input    [BYTE_CNT_WD-1 : 0]    byte_insert_cnt,
    output   reg                    ready_insert
    

);

        // signals 
        reg                         buf_valid; // 指示缓存有数据
        reg  [DATA_WD-1:0]          buf_data;  // 用于数据暂存

        wire [DATA_WD-1:0]          concatenated_data;  // 用于数据重组
         
        reg  [DATA_WD-1:0]          data_reg_last = 0;
        reg  [DATA_WD-1:0]          data_reg = 0;
        reg                         last_out_store = 0;// 标记最后一个数据到来
        reg                         last_out_reg = 0;
        reg  [DATA_BYTE_WD-1 : 0]   keep_out_store = 0;
        reg                         start_en;          // 指示接收到了header
        reg                         first = 0;         // 指示数据可以开始传输
        
        wire [BYTE_CNT_WD : 0]      ones_count_temp;
        integer                     byte_index;

         
        wire [32-1 : 0]   byte_cnt; // 表示keep_insert 1的个数，e.g. keep_insert（1110）--> byte_cnt(2)
        
        always @ (posedge clk or negedge rst_n) begin
            if(!rst_n) begin
                ready_insert <= 1;
                start_en <= 0;
            end
            else if(!start_en)
                ready_insert <= 1;
            else if(valid_insert) // 已经传来过了一个header数据
                ready_insert <= 0; 
        end
        
	always @(posedge clk or negedge rst_n) begin
            if(!rst_n)begin
                buf_valid <= 0;
                buf_data <= 0;
            end
            else if (valid_in && ready_in) begin// 有数据抵达但是输出端阻塞
                if(!ready_out && start_en) begin
                    buf_valid <= 1;
                    buf_data <=  data_in;
                end
            end
            else if (ready_out)
                    buf_valid <= 0;
	end
	
         // 用于数据表示和交互
        wire [DATA_WD-1:0]   data_temp;
        wire [DATA_WD-1:0]   data_temp_last;
        reg  [DATA_WD-1:0]   data_temp_store;
         
        always @ (posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            data_temp_store <= 0;
        end
        else begin
            data_temp_store <= data_temp ;

            end
        end
         
        assign  concatenated_data = ((data_temp_last & ((1 << (byte_cnt << 3)) - 1)) << (DATA_WD - (byte_cnt << 3))) | 
                                    ((data_temp & (((1 << ((DATA_BYTE_WD-byte_cnt) << 3)) - 1) << (byte_cnt << 3))) >>> (byte_cnt << 3));  // 位拼接逻辑

        
        assign  ready_in        =  start_en ? (last_out_store ? 0 : !buf_valid) : 0;
        // 判断逻辑 ：只有在接收到header才有效并且在接收到最后一个数据后不再接收
        assign  valid_out       =  first ? (rst_n && (valid_in || (buf_valid) || last_out_store)): 0;
        // 判断逻辑 ：只有在接收到data后才有效并且在接收到最后一个数据后保持有效指示最后一个数据到来
         
        assign  data_temp       =  start_en ? (last_out_reg ? data_reg_last : ((first ? ((ready_out && valid_out) ? (buf_valid ? buf_data : data_in) : data_temp) : data_reg))) : 0;
        assign  data_temp_last  =  start_en ? ((ready_out && valid_out) ? data_temp_store : data_temp_last) : 0;
         // 判断逻辑 ：         接收到header表示准备数据的传输start_en有效，否则data_temp为0-->
         // 若接收到的不是最后一拍数据，则进行第一拍数据的判断,否则data_temp为最后一拍数据-->
         // 如果已经接收到了第一拍数据，则进行buffer判断，查看数据是否在buffer中，否则data_temp为header数据
         // 由于数据需要重组拼接，需要在输出方未握手下保留前一拍数据，故进行握手判断
        assign  data_out        =  concatenated_data ; 
        assign  ones_count_temp =  count_one(keep_out_store);// 计算1的位数，通过线网连接即时更新
         
         
        // last_out_reg标记最后一个输入数据(可能含有最后一个数据的无效位)，(ones_count_temp + byte_cnt) <= DATA_BYTE_WD)时，表明加上header的发送数据数量和原数据相同
        assign  last_out        =  (((ones_count_temp + byte_cnt) <= DATA_BYTE_WD)) ?  (last_out_reg ? 0 : (last_out_store && (!buf_valid))) : last_out_reg;
        // 若不是最后一个数据，则所有位均有效
        assign  keep_out        =  last_out ? ((((ones_count_temp + byte_cnt) <= DATA_BYTE_WD)) ?  ((1 << (ones_count_temp + byte_cnt))-1) << (DATA_BYTE_WD-(ones_count_temp + byte_cnt)) :
                                              ((1 << (ones_count_temp + byte_cnt - DATA_BYTE_WD))-1) << (DATA_BYTE_WD - (ones_count_temp + byte_cnt - DATA_BYTE_WD))) : ((1 << DATA_BYTE_WD) - 1);

                  
        assign byte_cnt =  (!start_en) ? (byte_insert_cnt + 1) : byte_cnt;      
       
        always @(posedge clk or negedge rst_n) begin
            if(!rst_n) begin
                start_en   <=   1'b0;
                data_reg   <=   0;
                first <= 0;
                last_out_reg <= 0;
            end
            else begin
                if(valid_insert && ready_insert)begin 
                    if(!start_en)begin/// 还未开始传header并且插入握手成功
                        data_reg   <=   data_insert;
                        start_en   <=   1'b1;  
                    end
                end
                if(valid_in && ready_in)begin 
                    if(start_en && !first )begin// 第一次得到数据
                        first <= 1;    
                    end
                end
                if(ready_out && valid_out)begin 
                    if(last_out_store && !buf_valid)begin// 最后一次得到数据
                        if((ones_count_temp + byte_cnt) <= DATA_BYTE_WD)begin  // 若满足此条件，说明最后一个数据的keep_in和插入header的keep_insert的1bit的总和不超过DATA_BYTE_WD，总发送data数和发送方的data_in相同
                            last_out_reg <= 0;
                            first <= 0;
                            data_reg   <=   0;
                            start_en   <=   1'b0;
                            
                        end 
                        else begin
                            last_out_reg <= 1;
                        end
                    end
                    if(last_out_reg) begin// 完成一次传输
                        last_out_reg <= 0;
                        first <= 0;
                        data_reg   <=   0;
                        start_en   <=   1'b0;
                    end   
                end

            end
        end
        

                                
        always @(posedge last_in or negedge rst_n or negedge start_en) begin
                if(!rst_n) begin
                    data_reg_last <= 0; // 寄存最后一个数据
                end
                if(last_in && first) begin    // 接收到最后一个数据        
                        for (byte_index = 0; byte_index < DATA_BYTE_WD; byte_index = byte_index + 1) begin
                            data_reg_last[((byte_index << 3) + 7) -: 8] <= (keep_in[byte_index] == 1) ? data_in[((byte_index << 3) + 7) -: 8] : 8'b0;
                        end
                        last_out_store <= 1;
                        keep_out_store <= keep_in;          
                end
                if(!last_out_reg && !start_en) begin// 完成一次传输
                    last_out_store <= 0;
                end  
        end


        //           1-bit 计算模块
        function [DATA_BYTE_WD-1:0] count_one;
                input[DATA_BYTE_WD-1:0] binary_number;

                reg [DATA_BYTE_WD-1:0] xor_number;
                begin
                    xor_number = binary_number ^ {(DATA_BYTE_WD){1'b1}};
                    count_one = (DATA_BYTE_WD) - $clog2(xor_number + 1);
                end
  
        endfunction  
        
    
endmodule
