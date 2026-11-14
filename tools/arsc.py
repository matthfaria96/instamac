#!/usr/bin/env python3
"""arsc.py <apk|resources.arsc> <comando> ... -- consulta a tabela de recursos de um APK.

  name 0x7f0b4097            nome do recurso (tipo/chave)
  values 0x7f07xxxx          valor em cada configuração (-large, -sw600dp, ...)
  find REGEX [tipo]          ids cujo nome casa (opcional: só o tipo, ex. dimen)
  style 0x7f15xxxx [ATTR]    itens de um estilo/tema (opcional: só o atributo)
  styles-with 0x7f04xxxx     estilos que definem esse atributo, e com que valor

Não há aapt2 nesta máquina; isto lê o formato binário direto (tabela, pacotes,
type/typeSpec, entradas simples, compactas e mapas; offsets 32/16 bits e
esparsos). Valores de referência são impressos como @0x... e resolvidos um
nível quando o comando é `values`.
"""
import re
import struct
import sys
import zipfile

UNITS = ["px", "dp", "sp", "pt", "in", "mm"]
RADIX = [1.0, 1 / 128.0, 1 / 32768.0, 1 / 8388608.0]
SIZES = {1: "small", 2: "normal", 3: "large", 4: "xlarge"}


def read_pool(buf, off):
    hdr_size = struct.unpack_from("<H", buf, off + 2)[0]
    n_str, _n_style, flags, strs, _styles = struct.unpack_from("<IIIII", buf, off + 8)
    utf8 = bool(flags & 0x100)
    offs = struct.unpack_from("<%dI" % n_str, buf, off + hdr_size)
    base = off + strs
    out = []
    for o in offs:
        p = base + o
        if utf8:
            n = buf[p]; p += 1
            if n & 0x80: p += 1
            n = buf[p]; p += 1
            if n & 0x80: n = ((n & 0x7F) << 8) | buf[p]; p += 1
            out.append(buf[p:p + n].decode("utf-8", "replace"))
        else:
            n = struct.unpack_from("<H", buf, p)[0]; p += 2
            if n & 0x8000: n = ((n & 0x7FFF) << 16) | struct.unpack_from("<H", buf, p)[0]; p += 2
            out.append(buf[p:p + 2 * n].decode("utf-16-le", "replace"))
    return out


def config_name(buf, off):
    size = struct.unpack_from("<I", buf, off)[0]
    c = buf[off:off + size] + b"\0" * 64
    parts = []
    lang = c[8:10].rstrip(b"\0"); country = c[10:12].rstrip(b"\0")
    if lang:
        parts.append(lang.decode("latin1") + ("-r" + country.decode("latin1") if country else ""))
    orientation, _touch, density = struct.unpack_from("<BBH", c, 12)
    _sw_px, _sh_px, sdk, _minor = struct.unpack_from("<HHHH", c, 20)
    layout, ui_mode, swdp, wdp, hdp = struct.unpack_from("<BBHHH", c, 28)
    if swdp: parts.append("sw%ddp" % swdp)
    if wdp: parts.append("w%ddp" % wdp)
    if hdp: parts.append("h%ddp" % hdp)
    if layout & 0x0F: parts.append(SIZES.get(layout & 0x0F, "size%d" % (layout & 0x0F)))
    if layout & 0x30: parts.append({0x10: "notlong", 0x20: "long"}.get(layout & 0x30, "?"))
    if layout & 0xC0: parts.append({0x40: "ldltr", 0x80: "ldrtl"}.get(layout & 0xC0, "?"))
    if orientation: parts.append({1: "port", 2: "land", 3: "square"}.get(orientation, "?"))
    if ui_mode & 0x0F: parts.append({1: "", 2: "desk", 3: "car", 4: "television", 6: "watch"}.get(ui_mode & 0x0F, "ui?"))
    if ui_mode & 0x30: parts.append({0x10: "notnight", 0x20: "night"}.get(ui_mode & 0x30, "?"))
    if density: parts.append({120: "ldpi", 160: "mdpi", 240: "hdpi", 320: "xhdpi", 480: "xxhdpi",
                              640: "xxxhdpi", 0xFFFE: "anydpi", 0xFFFF: "nodpi"}.get(density, "%ddpi" % density))
    if sdk: parts.append("v%d" % sdk)
    return "-".join(p for p in parts if p) or "(default)"


def fmt_value(dtype, data, strings):
    if dtype == 0x01: return "@0x%08x" % data
    if dtype == 0x02: return "?0x%08x" % data
    if dtype == 0x03: return repr(strings[data]) if data < len(strings) else "str#%d" % data
    if dtype == 0x04: return "%g" % struct.unpack("<f", struct.pack("<I", data))[0]
    if dtype == 0x05:
        mant = struct.unpack("<i", struct.pack("<I", data & 0xFFFFFF00))[0] >> 8
        return "%g%s" % (mant * RADIX[(data >> 4) & 3], UNITS[data & 0xF] if (data & 0xF) < 6 else "?")
    if dtype == 0x06:
        mant = struct.unpack("<i", struct.pack("<I", data & 0xFFFFFF00))[0] >> 8
        return "%g%%" % (mant * RADIX[(data >> 4) & 3] * 100)
    if dtype == 0x10: return str(struct.unpack("<i", struct.pack("<I", data))[0])
    if dtype == 0x11: return "0x%x" % data
    if dtype == 0x12: return "true" if data else "false"
    if 0x1C <= dtype <= 0x1F: return "#%08x" % data
    if dtype == 0x00: return "(null)" if data == 0 else "(empty)"
    return "type0x%02x:0x%08x" % (dtype, data)


class Table:
    def __init__(self, buf):
        self.buf = buf
        self.strings = []
        self.names = {}     # id -> "type/key"
        self.entries = {}   # id -> [(config, kind, payload)]
        self.parse()

    def parse(self):
        buf = self.buf
        off = struct.unpack_from("<H", buf, 2)[0]
        end = struct.unpack_from("<I", buf, 4)[0]
        while off < end:
            ctype, hsize, csize = struct.unpack_from("<HHI", buf, off)
            if ctype == 0x0001 and not self.strings:
                self.strings = read_pool(buf, off)
            elif ctype == 0x0200:
                self.parse_package(off, hsize, csize)
            off += csize

    def parse_package(self, off, hsize, csize):
        buf = self.buf
        pkg_id = struct.unpack_from("<I", buf, off + 8)[0]
        type_strs_off, _lpt, key_strs_off = struct.unpack_from("<III", buf, off + 8 + 4 + 256)
        types = read_pool(buf, off + type_strs_off)
        keys = read_pool(buf, off + key_strs_off)
        p, end = off + hsize, off + csize
        while p < end:
            ctype, chsize, ccsize = struct.unpack_from("<HHI", buf, p)
            if ctype == 0x0201:
                tid, tflags, _res, n_entries, entries_start = struct.unpack_from("<BBHII", buf, p + 8)
                cfg = config_name(buf, p + 20)
                tname = types[tid - 1] if tid - 1 < len(types) else "type%d" % tid
                idx_off = p + chsize
                pairs = []
                if tflags & 0x01:      # sparse: (idx16, offset16/4)
                    for i in range(n_entries):
                        idx, o = struct.unpack_from("<HH", buf, idx_off + 4 * i)
                        pairs.append((idx, o * 4))
                elif tflags & 0x02:    # 16-bit offsets
                    for i in range(n_entries):
                        o = struct.unpack_from("<H", buf, idx_off + 2 * i)[0]
                        if o != 0xFFFF: pairs.append((i, o * 4))
                else:
                    for i in range(n_entries):
                        o = struct.unpack_from("<I", buf, idx_off + 4 * i)[0]
                        if o != 0xFFFFFFFF: pairs.append((i, o))
                for idx, o in pairs:
                    e = p + entries_start + o
                    size, flags, key = struct.unpack_from("<HHI", buf, e)
                    rid = (pkg_id << 24) | (tid << 16) | idx
                    if flags & 0x0008:   # compact: key16 in `size`, type in flags>>8, data in `key`
                        self.names.setdefault(rid, "%s/%s" % (tname, keys[size] if size < len(keys) else "?"))
                        self.entries.setdefault(rid, []).append((cfg, "v", (flags >> 8, key)))
                        continue
                    self.names.setdefault(rid, "%s/%s" % (tname, keys[key] if key < len(keys) else "?"))
                    if flags & 0x0001:
                        parent, count = struct.unpack_from("<II", buf, e + 8)
                        items = []
                        for i in range(count):
                            name, _vs, _r0, dtype, data = struct.unpack_from("<IHBBI", buf, e + 16 + 12 * i)
                            items.append((name, dtype, data))
                        self.entries.setdefault(rid, []).append((cfg, "m", (parent, items)))
                    else:
                        _vs, _r0, dtype, data = struct.unpack_from("<HBBI", buf, e + size)
                        self.entries.setdefault(rid, []).append((cfg, "v", (dtype, data)))
            p += ccsize

    def name(self, rid):
        return self.names.get(rid, "?")


def load(path):
    if zipfile.is_zipfile(path):
        with zipfile.ZipFile(path) as z:
            return Table(z.read("resources.arsc"))
    return Table(open(path, "rb").read())


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    t = load(sys.argv[1])
    cmd, args = sys.argv[2], sys.argv[3:]
    if cmd == "name":
        for a in args:
            print("0x%08x %s" % (int(a, 0), t.name(int(a, 0))))
    elif cmd == "values":
        for a in args:
            rid = int(a, 0)
            print("0x%08x %s" % (rid, t.name(rid)))
            for cfg, kind, payload in t.entries.get(rid, []):
                if kind == "v":
                    v = fmt_value(payload[0], payload[1], t.strings)
                    if payload[0] == 0x01 and payload[1] in t.entries:
                        v += "  -> %s: %s" % (t.name(payload[1]), "; ".join(
                            "%s=%s" % (c2, fmt_value(p2[0], p2[1], t.strings))
                            for c2, k2, p2 in t.entries[payload[1]] if k2 == "v"))
                    print("  %-28s %s" % (cfg, v))
                else:
                    print("  %-28s (mapa, %d itens, pai 0x%08x)" % (cfg, len(payload[1]), payload[0]))
    elif cmd == "find":
        pat = re.compile(args[0])
        want = args[1] if len(args) > 1 else None
        for rid in sorted(t.names):
            n = t.names[rid]
            if (not want or n.startswith(want + "/")) and pat.search(n):
                print("0x%08x %s" % (rid, n))
    elif cmd == "style":
        rid = int(args[0], 0)
        only = int(args[1], 0) if len(args) > 1 else None
        seen = set()
        while rid and rid not in seen:
            seen.add(rid)
            print("0x%08x %s" % (rid, t.name(rid)))
            parent = 0
            for cfg, kind, payload in t.entries.get(rid, []):
                if kind != "m":
                    continue
                parent = parent or payload[0]
                for name, dtype, data in payload[1]:
                    if only is None or name == only:
                        print("  [%s] 0x%08x %s = %s" % (cfg, name, t.name(name), fmt_value(dtype, data, t.strings)))
            if only is None:
                if parent: print("  pai: 0x%08x %s" % (parent, t.name(parent)))
                break
            rid = parent
    elif cmd == "styles-with":
        attr = int(args[0], 0)
        for rid in sorted(t.entries):
            for cfg, kind, payload in t.entries[rid]:
                if kind != "m":
                    continue
                for name, dtype, data in payload[1]:
                    if name == attr:
                        print("0x%08x %-60s [%s] = %s" % (rid, t.name(rid), cfg, fmt_value(dtype, data, t.strings)))
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
