module top(
    input sys_clk,
    input reset_btn,
    input uart_rx_i,
    output uart_tx_o,
    output led0_n,
    output led1_n
);

parameter TP = 78;
parameter QW = 19;

wire clk = sys_clk;
genvar i;

reg r1 = 1, r2 = 1;
always @(posedge clk) begin
    r1 <= uart_rx_i;
    r2 <= r1;
end
wire nr;
DFFR f19 (.D(1'b1), .CLK(clk), .RESET(r1), .Q(nr));

localparam [6:0] CL = 128 - TP;
wire [6:0] c;
wire [6:0] cn = {1'b0, c[6:1]} + c[0];
wire tick = cn[6];
DFFR f17 (.D(1'b1), .CLK(clk), .RESET(c[0]), .Q(c[0]));
generate for (i = 1; i < 7; i = i + 1) begin : cnt
    if (CL[i]) begin : one
        DFFS f (.D(cn[i-1]), .CLK(clk), .SET(tick), .Q(c[i]));
    end else begin : zero
        DFFR f (.D(cn[i-1]), .CLK(clk), .RESET(tick), .Q(c[i]));
    end
end
endgenerate
wire ntick;
wire [7:0] tc;
assign tc[0] = 1'b1;
generate for (i = 0; i < 7; i = i + 1) begin : tch
    ALU #(.ALU_MODE(2)) a (.I0(c[i]), .I1(1'b0), .I3(1'b1), .CIN(tc[i]), .COUT(tc[i+1]), .SUM());
end
endgenerate
ALU #(.ALU_MODE(2)) tco (.I0(1'b1), .I1(1'b0), .I3(1'b1), .CIN(tc[7]), .COUT(), .SUM(ntick));

reg [27:1] m = 0;
wire m0;
wire [27:0] bc;
wire busy;
assign bc[0] = 1'b0;
generate for (i = 1; i < 28; i = i + 1) begin : bzc
    ALU #(.ALU_MODE(2)) a (.I0(m[i]), .I1(1'b1), .I3(1'b1), .CIN(bc[i-1]), .COUT(bc[i]), .SUM());
end
endgenerate
ALU #(.ALU_MODE(2)) bzo (.I0(1'b0), .I1(1'b0), .I3(1'b1), .CIN(bc[27]), .COUT(), .SUM(busy));
DFFRE f0 (.D(nr), .CLK(clk), .CE(tick), .RESET(busy), .Q(m0));
always @(posedge clk) if (tick) m <= {m[26:1], m0};

reg [24:0] s = 0;
always @(posedge clk) if (tick) s <= {s[23:0], r2};
wire [7:0] byt = {s[3], s[6], s[9], s[12], s[15], s[18], s[21], s[24]};

wire e;
DFFRE f1 (.D(m[27]), .CLK(clk), .CE(tick), .RESET(ntick), .Q(e));

wire [QW-1:0] q;
wire [QW-1:0] qn = {1'b0, q[QW-1:1]} + q[0];
wire to = qn[QW-1];
DFFR f18 (.D(1'b1), .CLK(clk), .RESET(q[0]), .Q(q[0]));
generate for (i = 1; i < QW; i = i + 1) begin : qc
    DFFR f (.D(qn[i-1]), .CLK(clk), .RESET(e), .Q(q[i]));
end
endgenerate

localparam [31:0] KP = {8'b01101111, 8'b11111100, 8'b11011111, 8'b11111110};
wire [31:0] kr;
wire [7:0] kt = kr[31:24];
wire [7:0] ki = kr[23:16];
wire [7:0] k5 = kr[15:8];
wire [7:0] k0 = kr[7:0];
generate for (i = 0; i < 32; i = i + 1) begin : rings
    if (KP[i]) begin : one
        DFFSE f (.D(kr[(i % 8 == 7) ? i - 7 : i + 1]), .CLK(clk), .CE(e), .SET(to), .Q(kr[i]));
    end else begin : zero
        DFFRE f (.D(kr[(i % 8 == 7) ? i - 7 : i + 1]), .CLK(clk), .CE(e), .RESET(to), .Q(kr[i]));
    end
end
endgenerate

wire trig, ei;
DFFR f2 (.D(e), .CLK(clk), .RESET(kt[0]), .Q(trig));
DFFR f3 (.D(e), .CLK(clk), .RESET(ki[0]), .Q(ei));

reg [63:0] p = 0;
reg [23:0] lin = 0;
reg [15:0] ix = 0;
always @(posedge clk) begin
    if (e) p <= {p[55:0], byt};
    if (e) lin <= {lin[15:0], byt};
    if (ei) ix <= {ix[7:0], byt};
end

wire [16:0] fc;
wire first, warm;
assign fc[0] = 1'b0;
generate for (i = 0; i < 16; i = i + 1) begin : fzc
    ALU #(.ALU_MODE(2)) a (.I0(ix[i]), .I1(1'b1), .I3(1'b1), .CIN(fc[i]), .COUT(fc[i+1]), .SUM());
end
endgenerate
ALU #(.ALU_MODE(2)) fzo (.I0(1'b1), .I1(1'b0), .I3(1'b1), .CIN(fc[16]), .COUT(), .SUM(first));
wire [12:0] wc;
assign wc[0] = 1'b0;
generate for (i = 0; i < 12; i = i + 1) begin : wzc
    ALU #(.ALU_MODE(2)) a (.I0(ix[i+4]), .I1(1'b1), .I3(1'b1), .CIN(wc[i]), .COUT(wc[i+1]), .SUM());
end
endgenerate
ALU #(.ALU_MODE(2)) wzo (.I0(1'b1), .I1(1'b0), .I3(1'b1), .CIN(wc[12]), .COUT(), .SUM(warm));

wire item = lin[17];
wire nitem = lin[16];
wire [15:0] price = lin[15:0];

reg [7:1] z = 0;
always @(posedge clk) z <= {z[6:1], trig};

wire wa, wb;
DFFR f4 (.D(z[6]), .CLK(clk), .RESET(item), .Q(wa));
DFFR f5 (.D(z[6]), .CLK(clk), .RESET(nitem), .Q(wb));

wire [31:0] wo;
wire [39:0] tdo;
wire a1n, a0n;
reg [19:0] tr = 0;
wire [19:0] nsum = tr + {4'd0, price};
wire [39:0] tdi = {2'b0, nsum, price, a1n, a0n};
generate for (i = 0; i < 4; i = i + 1) begin : wram
    RAM16SDP4 ra (.DO(wo[4*i+3:4*i]), .DI(price[4*i+3:4*i]), .WAD(ix[3:0]), .RAD(ix[3:0]), .WRE(wa), .CLK(clk));
    RAM16SDP4 rb (.DO(wo[4*i+19:4*i+16]), .DI(price[4*i+3:4*i]), .WAD(ix[3:0]), .RAD(ix[3:0]), .WRE(wb), .CLK(clk));
end
for (i = 0; i < 10; i = i + 1) begin : tram
    RAM16SDP4 rt (.DO(tdo[4*i+3:4*i]), .DI(tdi[4*i+3:4*i]), .WAD({3'b0, item}), .RAD({3'b0, item}), .WRE(z[7]), .CLK(clk));
end
endgenerate

wire [19:0] sm;
wire [15:0] ga, gb;
reg [15:0] pv = 0;
reg [1:0] ac = 0;
always @(posedge clk) begin
    if (trig) pv <= tdo[17:2];
    if (trig) ac <= tdo[1:0];
end
generate for (i = 0; i < 20; i = i + 1) begin : smr
    DFFRE f (.D(tdo[18+i]), .CLK(clk), .CE(trig), .RESET(first), .Q(sm[i]));
end
for (i = 0; i < 16; i = i + 1) begin : gab
    DFFRE fa (.D(wo[i]), .CLK(clk), .CE(trig), .RESET(item), .Q(ga[i]));
    DFFRE fb (.D(wo[16+i]), .CLK(clk), .CE(trig), .RESET(nitem), .Q(gb[i]));
end
endgenerate

wire [15:0] h, od;
generate for (i = 0; i < 16; i = i + 1) begin : oldg
    DFFS fh (.D(ga[i]), .CLK(clk), .SET(gb[i]), .Q(h[i]));
    DFFR fo (.D(h[i]), .CLK(clk), .RESET(warm), .Q(od[i]));
end
endgenerate

always @(posedge clk) tr <= sm - {4'd0, od};

wire [15:0] oavg = sm[19:4];
wire [15:0] navg = nsum[19:4];
wire l1, l2, l3, l4, l5, l6, l7, l8;
ltc #(17) cp1 (.a({warm, navg}), .b({1'b0, price}), .y(l1));
ltc #(17) cp2 (.a({warm, price}), .b({1'b0, navg}), .y(l2));
ltc #(17) cp3 (.a({1'b0, navg}), .b({warm, price}), .y(l3));
ltc #(17) cp4 (.a({1'b0, price}), .b({warm, navg}), .y(l4));
ltc #(16) cp5 (.a(oavg), .b(pv), .y(l5));
ltc #(16) cp6 (.a(pv), .b(oavg), .y(l6));
ltc #(17) cp7 (.a({warm, oavg}), .b({1'b0, pv}), .y(l7));
ltc #(17) cp8 (.a({warm, pv}), .b({1'b0, oavg}), .y(l8));

wire ua, da, uaw, daw, a1m, a0m;
DFFR f6 (.D(l1), .CLK(clk), .RESET(l5), .Q(ua));
DFFR f7 (.D(l2), .CLK(clk), .RESET(l6), .Q(da));
DFFR f8 (.D(l3), .CLK(clk), .RESET(l7), .Q(uaw));
DFFR f9 (.D(l4), .CLK(clk), .RESET(l8), .Q(daw));
DFFR f10 (.D(ac[1]), .CLK(clk), .RESET(daw), .Q(a1m));
DFFR f11 (.D(ac[0]), .CLK(clk), .RESET(uaw), .Q(a0m));
DFFS f12 (.D(a1m), .CLK(clk), .SET(ua), .Q(a1n));
DFFS f13 (.D(a0m), .CLK(clk), .SET(da), .Q(a0n));

wire s1g, ldp;
DFFR f14 (.D(z[6]), .CLK(clk), .RESET(k5[0]), .Q(s1g));
DFFR f15 (.D(z[6]), .CLK(clk), .RESET(k0[0]), .Q(ldp));
reg [1:0] ah = 0;
always @(posedge clk) if (s1g) ah <= {a1n, a0n};
reg ld = 0;
always @(posedge clk) ld <= ldp;

wire [35:0] src = {p[63:56], p[55:48], p[47:40], ah, p[23:16], a1n, a0n};
wire [35:0] x;
generate for (i = 0; i < 36; i = i + 1) begin : xg
    DFFR fx (.D(ldp), .CLK(clk), .RESET(src[i]), .Q(x[i]));
end
endgenerate

wire [2:0] y;
DFFSE y0 (.D(y[2]), .CLK(clk), .CE(tick), .SET(to), .Q(y[0]));
DFFRE y1 (.D(y[0]), .CLK(clk), .CE(tick), .RESET(to), .Q(y[1]));
DFFRE y2 (.D(y[1]), .CLK(clk), .CE(tick), .RESET(to), .Q(y[2]));
wire bt;
DFFRE f16 (.D(y[0]), .CLK(clk), .CE(tick), .RESET(ntick), .Q(bt));

wire [168:0] rs;
wire [168:0] R;
assign rs[168] = 1'b0;
generate for (i = 0; i < 8; i = i + 1) begin : lay
    assign rs[167-21*i] = ld;
    assign rs[158-21*i:147-21*i] = 12'd0;
end
endgenerate
generate for (i = 0; i < 8; i = i + 1) begin : dat
    assign rs[166-i] = x[28+i];
    assign rs[145-i] = x[20+i];
    assign rs[124-i] = x[12+i];
    assign rs[82-i] = x[2+i];
    assign rs[40-i] = ld;
    assign rs[19-i] = ld;
end
endgenerate
assign rs[103] = x[10];
assign rs[102] = x[11];
assign rs[101:96] = {6{ld}};
assign rs[61] = x[0];
assign rs[60] = x[1];
assign rs[59:54] = {6{ld}};

DFFRE t0 (.D(1'b1), .CLK(clk), .CE(bt), .RESET(rs[0]), .Q(R[0]));
generate for (i = 1; i < 169; i = i + 1) begin : txr
    DFFRE tf (.D(R[i-1]), .CLK(clk), .CE(bt), .RESET(rs[i]), .Q(R[i]));
end
endgenerate

wire boot, txq;
DFFSE fb (.D(1'b0), .CLK(clk), .CE(to), .SET(1'b0), .Q(boot));
DFFS ft (.D(R[168]), .CLK(clk), .SET(boot), .Q(txq));

assign uart_tx_o = txq;
assign led0_n = ~(busy | m0);
assign led1_n = 1;

endmodule

module ltc #(parameter N = 17) (input [N-1:0] a, input [N-1:0] b, output y);
wire [N:0] c;
assign c[0] = 1'b1;
genvar k;
generate for (k = 0; k < N; k = k + 1) begin : ch
    ALU #(.ALU_MODE(2)) u (.I0(a[k]), .I1(b[k]), .I3(1'b0), .CIN(c[k]), .COUT(c[k+1]), .SUM());
end
endgenerate
ALU #(.ALU_MODE(2)) o (.I0(1'b1), .I1(1'b0), .I3(1'b1), .CIN(c[N]), .COUT(), .SUM(y));
endmodule
