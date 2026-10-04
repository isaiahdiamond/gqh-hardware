import sys

TKN = 1872
TPB = 78
LIM = 270
GAP = 11
ZP = 127
ZS = 63
ZW = 16

IDX, AND, MOV, ADD, CMP, ACT1, ACT0, NOP = range(8)


def pack(fields, layout):
    v = 0
    for name, (lo, w) in layout.items():
        x = fields.get(name, 0)
        assert 0 <= x < (1 << w), (name, x)
        v |= x << lo
    return v


def lay(spec):
    out, lo = {}, 0
    for name, w in spec:
        out[name] = (lo, w)
        lo += w
    return out, lo


def tk():
    rom = {}
    for s in range(TKN):
        n = (s + 1) % TKN
        rom[s] = n | ((n % TPB == TPB - 1) << 11) | ((n % (3 * TPB) == 3 * TPB - 1) << 12) | ((n == TKN - 1) << 13)
    return rom


def to():
    rom = {}
    for c in range(512):
        for st in range(2):
            for clr in range(2):
                if clr:
                    n = 0
                elif st:
                    n = min(c + 1, LIM)
                else:
                    n = min(c, LIM)
                rom[(c << 2) | (st << 1) | clr] = n | ((n == LIM) << 9)
    return rom


RXL, RXW = lay([("st", 9), ("pwa", 7), ("pwe", 1), ("pxi", 1), ("pxt", 1), ("clr", 1), ("done", 1)])


def pbaddr(k, b):
    return [8 + b, b, 16 + b, 72 + b, 64 + b, 24 + b, 104 + b, 96 + b][k]


def rxm():
    st = {}
    names = []

    free = [i for i in range(512) if i % 256 >= 8]

    def add(name, f, at=None):
        st[name] = (free.pop(0) if at is None else at, f)
        names.append(name)

    add("W0", {"clr": 1}, 0)
    for k in range(8):
        if k:
            add(f"W{k}", {}, k)
        add(f"T{k}_1", {"clr": int(k == 0)}, 256 + k)
        for c in range(2, 29):
            add(f"T{k}_{c}", {"clr": 1})
        for b in range(8):
            a = pbaddr(k, b)
            add(f"S{k}_{b}", {"clr": 1, "pwa": a, "pwe": 1, "pxi": int(k == 1 and b < 4), "pxt": int(k in (2, 5) and b == 0)})
    add("D", {"clr": 1, "done": 1})

    def nxt(name, r, tick, tov):
        if name[0] == "W":
            k = int(name[1:])
            if k and tov:
                return "W0"
            if tick and not r:
                return f"T{k}_1"
            return name
        if name == "D":
            return "T7_26"
        if name == "S7_7":
            return "D"
        if name[0] == "S":
            k, b = map(int, name[1:].split("_"))
            return f"T{k}_{5 + 3 * b}"
        k, c = map(int, name[1:].split("_"))
        if not tick:
            return name
        if c == 28:
            return "W0" if k == 7 else f"W{k + 1}"
        if c >= 4 and (c - 4) % 3 == 0 and (c - 4) // 3 < 8:
            b = (c - 4) // 3
            return f"S{k}_{b}"
        return f"T{k}_{c + 1}"


    rom = {}
    for name, (idx, f) in st.items():
        for r in range(2):
            for tick in range(2):
                for tov in range(2):
                    n = nxt(name, r, tick, tov)
                    ni, nf = st[n]
                    d = dict(nf)
                    d["st"] = ni
                    rom[(idx << 3) | (r << 2) | (tick << 1) | tov] = pack(d, RXL)
    assert st["W0"][0] == 0
    return rom, len(names)


UCL, UCW = lay([("pc", 9), ("pa", 7), ("sa", 6), ("sb", 6), ("swa", 6), ("swe", 1), ("wr", 5), ("ww", 4), ("wwe", 1), ("op", 3), ("sel", 1), ("ok", 1)])


def micro(s):
    pb = 64 + 32 * s
    mo = []

    def m(**k):
        mo.append(k)

    m(op=MOV)
    for j in range(16):
        m(op=IDX, pa=j)
    for j in range(20):
        m(op=AND, sa=j, wr=ZW, swa=j)
    m(op=MOV)
    for j in range(4, 16):
        m(op=IDX, pa=j)
    for j in range(16):
        m(op=AND, sa=ZS, wr=j, ww=j)
    for j in range(20):
        m(op=ADD, pa=pb + j, sa=j, sb=j if j < 4 else 16 + j, wr=j, swa=j)
    for j in range(16):
        m(op=CMP, pa=pb + j, sa=4 + j)
    m(op=ACT1, sa=37, swa=37)
    m(op=ACT0, sa=36, swa=36)
    for j in range(16):
        m(op=MOV, pa=pb + j, sa=ZS, swa=20 + j, ww=j)
    return mo


def slot(s):
    mo = micro(s)
    n = len(mo) + 2 + 3
    tl = [dict(pa=ZP, sa=ZS, sb=ZS, wr=ZW, op=IDX, sel=s, ok=1) for _ in range(n)]
    for i, x in enumerate(mo):
        for key in ("pa", "sa", "sb", "wr"):
            if key in x:
                tl[i][key] = x[key]
        tl[i + 1]["op"] = x["op"]
        if "swa" in x:
            tl[i + 2]["swa"] = x["swa"]
            tl[i + 2]["swe"] = 1
        if "ww" in x:
            tl[i + 2]["ww"] = x["ww"]
            tl[i + 2]["wwe"] = 1
    return tl


def txbits():
    out = []
    for B in range(8):
        sel = int(B >= 4)
        base = dict(pa=ZP, sa=ZS, sb=ZS, wr=ZW, sel=sel, ok=1)
        out.append(dict(base, op=NOP))
        for i in range(8):
            d = dict(base, op=NOP)
            if B == 0:
                d["pa"] = 8 + i
            elif B == 1:
                d["pa"] = i
            elif B == 2:
                d["pa"] = 16 + i
            elif B == 4:
                d["pa"] = 24 + i
            elif B in (3, 5) and i < 2:
                d["sa"] = 36 + i
            out.append(d)
        for _ in range(GAP + 1 if B < 7 else 2):
            out.append(dict(base, op=IDX))
    return out


def uc():
    idle = dict(pa=ZP, sa=ZS, sb=ZS, wr=ZW, op=IDX, sel=0, ok=1)
    comp = slot(0) + slot(1)
    txw = dict(idle)
    tx = txbits()
    states = [("I", idle)] + [("C", c) for c in comp] + [("W", txw)] + [("X", t) for t in tx]
    assert len(states) <= 512, len(states)
    rom = {}
    n = len(states)
    for i, (kind, f) in enumerate(states):
        for done in range(2):
            for bt in range(2):
                if kind == "I":
                    j = 1 if done else 0
                elif kind == "C":
                    j = i + 1
                else:
                    j = (i + 1) % n if bt else i
                d = dict(states[j][1])
                d["pc"] = j
                rom[(i << 2) | (done << 1) | bt] = pack(d, UCL)
    return rom, n


def xrom():
    rom = {}
    for a in range(1 << 14):
        fl = a & 127
        w = (a >> 7) & 1
        sb = (a >> 8) & 1
        sa = (a >> 9) & 1
        pa = (a >> 10) & 1
        op = a >> 11
        b1, c2, g1g, g1l, g2g, g2l, nz = [(fl >> i) & 1 for i in range(7)]
        out, tx = 0, 1
        if op == IDX:
            nz |= pa
        elif op == AND:
            out = (sa | w) & nz
        elif op == NOP:
            tx = pa | sa
        elif op == MOV:
            out = pa | sa
            b1 = c2 = g1g = g1l = g2g = g2l = nz = 0
        elif op == ADD:
            t = sa - w - b1
            b1 = int(t < 0)
            t &= 1
            n = t + pa + c2
            c2 = n >> 1
            out = n & 1
            if sb != sa:
                g1g, g1l = (1, 0) if sb > sa else (0, 1)
        elif op == CMP:
            if pa != sa:
                g2g, g2l = (1, 0) if pa > sa else (0, 1)
        elif op in (ACT1, ACT0):
            up = (1 - g1g) & g2g
            dn = (1 - g1l) & g2l
            if op == ACT1:
                out = nz & (up | ((1 - dn) & sa))
            else:
                out = nz & (dn | ((1 - up) & sa))
        fl = b1 | (c2 << 1) | (g1g << 2) | (g1l << 3) | (g2g << 4) | (g2l << 5) | (nz << 6)
        rom[a] = fl | (out << 7) | (tx << 8)
    return rom


def inits(rom, abits, width, blk):
    depth = 1 << abits
    assert depth * width <= 16384
    bits = [0] * 16384
    for a, v in rom.items():
        assert a < depth
        x = (v >> (blk * width)) & ((1 << width) - 1)
        for i in range(width):
            if (x >> i) & 1:
                bits[a * width + i] = 1
    res = []
    for r in range(64):
        chunk = bits[r * 256:(r + 1) * 256]
        if any(chunk):
            val = sum(b << i for i, b in enumerate(chunk))
            res.append(f".INIT_RAM_{r:02X}(256'h{val:064X})")
    return res


def prom(name, rom, abits, width, nblk, ad, do):
    s = []
    for k in range(nblk):
        p = [".READ_MODE(1'b0)", f".BIT_WIDTH({width})", '.RESET_MODE("SYNC")'] + inits(rom, abits, width, k)
        s.append(f"pROM #({', '.join(p)}) {name}{k} (.DO({{nc_{name}{k}, {do}[{k * width + width - 1}:{k * width}]}}), .AD({ad}), .CLK(clk), .CE(1'b1), .OCE(1'b1), .RESET(1'b0));")
        s.insert(0, f"wire [{31 - width}:0] nc_{name}{k};")
    return s


def sdp(name, w0, w1, ada, di, cea, adb, do):
    return [f"wire [{31 - w1}:0] nc_{name};",
            f"SDPB #(.READ_MODE(1'b0), .BIT_WIDTH_0({w0}), .BIT_WIDTH_1({w1}), .BLK_SEL_0(3'b000), .BLK_SEL_1(3'b000), .RESET_MODE(\"SYNC\")) {name} (.DO({{nc_{name}, {do}}}), .DI({{31'b0, {di}}}), .BLKSELA(3'b000), .BLKSELB(3'b000), .ADA({ada}), .ADB({adb}), .CLKA(clk), .CLKB(clk), .CEA({cea}), .CEB(1'b1), .OCE(1'b1), .RESETA(1'b0), .RESETB(1'b0));"]


def main():
    rxr, nrx = rxm()
    ucr, nuc = uc()
    sys.stderr.write(f"rx states {nrx} uc states {nuc}\n")
    L = []
    L.append("module top(")
    L.append("    input sys_clk,")
    L.append("    input reset_btn,")
    L.append("    input uart_rx_i,")
    L.append("    output uart_tx_o,")
    L.append("    output led0_n,")
    L.append("    output led1_n")
    L.append(");")
    L.append("")
    L.append("wire clk = sys_clk;")
    L.append("wire r = uart_rx_i;")
    L.append("wire [15:0] tk;")
    L.append("wire [15:0] tq;")
    L.append(f"wire [{RXW - 1 + (-RXW) % 4}:0] rx;")
    L.append(f"wire [{UCW - 1 + (-UCW) % 8}:0] u;")
    L.append("wire [8:0] x;")
    L.append("wire pdo, ado, bdo, wdo, item;")
    L.append("wire [3:0] ix;")
    L.append("")
    L.append("")
    L += prom("tk", tk(), 11, 8, 2, "{tk[10:0], 3'b000}", "tk")
    L += prom("to", to(), 11, 8, 2, "{tq[8:0], tk[13], rx[19], 3'b000}", "tq")
    L += prom("rm", rxr, 12, 4, (RXW + 3) // 4, "{rx[8:0], r, tk[11], tq[9], 2'b00}", "rx")
    L += prom("uc", ucr, 11, 8, (UCW + 7) // 8, "{u[8:0], rx[20], tk[12], 3'b000}", "u")
    L += prom("xr", xrom(), 14, 1, 9, "{u[47:45], pdo, ado, bdo, wdo, x[6:0]}", "x")
    L += sdp("pb", 1, 1, "{7'b0, rx[15:9]}", "r", "rx[16]", "{7'b0, u[15:9]}", "pdo")
    L += sdp("pi", 1, 4, "{12'b0, rx[10:9]}", "r", "rx[17]", "14'b0", "ix")
    L += sdp("pt", 1, 1, "{13'b0, rx[12]}", "r", "rx[18]", "{13'b0, u[48]}", "item")
    L += sdp("sa", 1, 1, "{7'b0, item, u[33:28]}", "x[7]", "u[34]", "{7'b0, item, u[21:16]}", "ado")
    L += sdp("sb", 1, 1, "{7'b0, item, u[33:28]}", "x[7]", "u[34]", "{7'b0, item, u[27:22]}", "bdo")
    L += sdp("wm", 1, 1, "{4'b0, item, ix, 1'b0, u[43:40]}", "x[7]", "u[44]", "{4'b0, item, ix, u[39:35]}", "wdo")
    L.append("")
    L.append("assign uart_tx_o = x[8];")
    L.append("assign led0_n = 1'b1;")
    L.append("assign led1_n = 1'b1;")
    L.append("")
    L.append("endmodule")
    print("\n".join(L))


main()
