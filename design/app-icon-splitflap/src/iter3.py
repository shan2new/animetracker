TITLE = "Iteration 3 — air round the letter; the light board's letter as solid ink so it survives the tinted modes"
P = dict(mods=[(158, 644), (666, 866)], top=202, bot=822, seam0=506, seam1=518, flap_r=38, seam_r=6,
         p_cx=407, p_w=304, cap0=272, cap1=750, stem=94, bowl=62, bowl_gap=3, corner=10, counter_r=10,
         dot=(766, 703), dot_r=47, dot_shadow=0.5, ink_shadow=0.3,
         pins="round", pin_off=6, pin_r=13, crown=0.10, edge_light=0.30, cast=0.32, cast_len=56,
         flap_tr=0.22, flap_blur=0.35, housing=None)
DARK = dict(top0=0x42404B, top1=0x33313B, bot0=0x2A2830, bot1=0x1E1D23, ink=0xF7F1E6, dot=0xFF5A45, pin=0x6E6C78, housing=0x0A0A0D,
            g0=0x0E0E12, g1=0x1B1A21, glow=(512, 100, 340, 0x3A3848, 0.55))
LIGHT = dict(top0=0xFFFFFF, top1=0xF5F1EA, bot0=0xEDE8DF, bot1=0xE2DBCF, ink=0x131318, dot=0xFF5A45, pin=0x9C9385, housing=0xCFC6B6,
             g0=0xE2DACC, g1=0xC9BEAB, glow=(512, 100, 360, 0xFFFFFF, 0.5), ink_glass=False)
