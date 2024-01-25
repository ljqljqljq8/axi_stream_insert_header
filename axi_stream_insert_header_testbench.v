module skid_sim;
  reg clk;
  reg rst_n;

  // AXI Stream input original data
  reg                    valid_in;
  reg  [16-1:0]          data_in;
  reg  [2-1:0]           keep_in;
  reg                    last_in;
  wire                   ready_in;

  // AXI Stream output with header inserted
  wire                   valid_out;
  wire  [16-1:0]         data_out;
  wire  [2-1:0]          keep_out;
  wire                   last_out;  
  reg                    ready_out;

  reg                    valid_insert;
  reg  [16-1:0]          data_insert;
  reg  [2-1:0]           keep_insert;
  reg  [1-1:0]           byte_insert_cnt;
  wire                   ready_insert;

  axi_stream_insert_header #(
    .DATA_WD(16)
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

          initial begin
                clk = 0;
                forever #2 clk = ~clk;
          end
          
          
        // Reset and initialization
          initial begin
                rst_n = 0;
                valid_in = 0;
                data_in = 255*32;
                last_in = 0;
            
                ready_out = 0;
            
                valid_insert = 0;
                data_insert = 0;
                keep_insert = 0;
                byte_insert_cnt = 0;
            
                #10 rst_n = 1;
                #15 data_insert = 56;
                byte_insert_cnt = 1;
                #20 @(posedge clk);
                valid_insert = 1;
          end
        
          reg [9:0] cnt;
        
         // Input data generation
          always @(posedge clk) begin
            if (!rst_n) begin
              cnt <= 0;
              last_in <= 0;
              keep_in <= 2'b00;
            end
            else begin
              if (ready_in) begin
                valid_in <= 1;
                if (cnt % 150 == 0 && cnt) begin
                  last_in <= 1;
                  keep_in <= 2'b10;
                end
              end
              else begin
                valid_in <= 0;
              end
              if (ready_in && valid_in)
                data_in <= data_in + 1;
              else
                data_in <= data_in;
              cnt <= cnt + 1;
            end
          end
        
          always @(posedge clk) begin
            if (!rst_n) begin
              cnt <= 0;
            end
            else begin
              if (cnt % 9 == 0) begin
                ready_out <= 0;
                @(posedge clk);
                @(posedge clk);
                @(posedge clk);
                ready_out <= 1;
              end
            end
          end
        
        // Display output data
          always @(posedge clk) begin
            if (ready_out && valid_out)
              $display("Data is: %h", data_out);
          end 
          
          
endmodule
