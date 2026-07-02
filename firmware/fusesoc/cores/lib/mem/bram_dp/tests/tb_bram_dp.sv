// tb_bram_dp.sv
module tb_bram_dp;

    parameter N = 4;  // 16 locations
    parameter B = 8;  // 8-bit data
    
    logic          clka, clkb;
    logic          ena, enb;
    logic          wea, web;
    logic [N-1:0]  addra, addrb;
    logic [B-1:0]  dia, dib;
    logic [B-1:0]  doa, dob;
    
    bram_dp #(.N(N), .B(B)) uut (
        .clka(clka), .clkb(clkb),
        .ena(ena),   .enb(enb),
        .wea(wea),   .web(web),
        .addra(addra), .addrb(addrb),
        .dia(dia),     .dib(dib),
        .doa(doa),     .dob(dob)
    );
    
    // Clock generation
    always #10 clka = ~clka;
    always #15 clkb = ~clkb;
    
    initial begin
        clka = 0; clkb = 0;
        ena = 0; enb = 0;
        wea = 0; web = 0;
        
        // Write to port A
        @(posedge clka);
        ena = 1; wea = 1; addra = 5; dia = 8'h42;
        @(posedge clka);
        wea = 0;
        
        // Read from port A
        addra = 5;
        @(posedge clka);
        $display("Read from A: data = %h (expected 42)", doa);
        
        // Write to port B
        @(posedge clkb);
        enb = 1; web = 1; addrb = 10; dib = 8'hAB;
        @(posedge clkb);
        web = 0;
        
        // Read from port B
        addrb = 10;
        @(posedge clkb);
        $display("Read from B: data = %h (expected AB)", dob);
        
        $finish;
    end

endmodule
