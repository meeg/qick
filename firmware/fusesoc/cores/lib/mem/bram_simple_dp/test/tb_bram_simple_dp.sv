// tb_bram_simple_dp.sv
module tb_bram_simple_dp;

    parameter N = 4;  // 16 locations
    parameter B = 8;  // 8-bit data
    
    logic          clk;
    logic          ena, enb;
    logic          wea;
    logic [N-1:0]  addra, addrb;
    logic [B-1:0]  dia;
    logic [B-1:0]  dob;
    
    bram_simple_dp #(.N(N), .B(B)) uut (
        .clk(clk),
        .ena(ena),
        .enb(enb),
        .wea(wea),
        .addra(addra),
        .addrb(addrb),
        .dia(dia),
        .dob(dob)
    );
    
    // Clock generation
    always #10 clk = ~clk;
    
    initial begin
        clk = 0;
        ena = 0; enb = 0;
        wea = 0;
        
        // Write to memory
        @(posedge clk);
        ena = 1; wea = 1; addra = 5; dia = 8'h42;
        @(posedge clk);
        ena = 0; wea = 0;
        
        // Read from memory
        @(posedge clk);
        enb = 1; addrb = 5;
        @(posedge clk);
        enb = 0;
        
        $display("Read from memory: data = %h (expected 42)", dob);
        
        // Write another value
        @(posedge clk);
        ena = 1; wea = 1; addra = 10; dia = 8'hAB;
        @(posedge clk);
        ena = 0; wea = 0;
        
        // Read the new value
        @(posedge clk);
        enb = 1; addrb = 10;
        @(posedge clk);
        enb = 0;
        
        $display("Read from memory: data = %h (expected AB)", dob);
        
        $finish;
    end

endmodule
