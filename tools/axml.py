#!/usr/bin/env python3
"""axml.py <base.apk> <comando> ... -- lê os layouts do APK (XML binário), inclusive
os que o Instagram empacota num blob próprio (assets/layouts.bin.*, xz).

  dump 0x7f0e0123            imprime o layout desse id (tags + atributos)
  dump layout/nome           idem, por nome
  with-id 0x7f0b30ed [N]     layouts cujo XML menciona esse id de recurso
                             (ex.: o android:id de uma view); imprime até N
  find-attr 0x7f040e04       layouts que usam esse atributo, com o valor

A tabela de recursos dá, para cada layout, um caminho (res/x.xml) ou um token
`L|<offset hex>|<tamanho hex>|...` que endereça o blob descompactado.
"""
import lzma
import struct
import sys
import zipfile

sys.path.insert(0, __file__.rsplit("/", 1)[0])
import arsc  # noqa: E402

TYPE_NAMES = {0x01: "@", 0x02: "?"}


class Apk:
    def __init__(self, path):
        self.zip = zipfile.ZipFile(path)
        self.table = arsc.Table(self.zip.read("resources.arsc"))
        self.blob = None

    def packed_blob(self):
        if self.blob is None:
            raw = None
            for name in ("assets/layouts.bin.xz", "assets/layouts.bin.spo", "assets/layouts.bin"):
                try:
                    raw = self.zip.read(name)
                    break
                except KeyError:
                    continue
            if raw is None:
                self.blob = b""
            else:
                at = raw.find(b"\xfd7zXZ\x00", 0, 4096)
                self.blob = lzma.decompress(raw[at:]) if at >= 0 else raw
        return self.blob

    def layout_bytes(self, rid):
        for _cfg, kind, payload in self.table.entries.get(rid, []):
            if kind != "v" or payload[0] != 0x03:
                continue
            path = self.table.strings[payload[1]]
            if len(path) > 2 and path[1] == "|":
                parts = path.split("|")
                off, length = int(parts[1], 16), int(parts[2], 16)
                return self.packed_blob()[off:off + length]
            try:
                return self.zip.read(path)
            except KeyError:
                return None
        return None

    def layouts(self):
        for rid, name in sorted(self.table.names.items()):
            if name.startswith("layout/"):
                yield rid, name


def parse(buf, table):
    """Yield (depth, tag, [(attr_name, attr_id, value_text)]) for each start tag."""
    if len(buf) < 8 or struct.unpack_from("<H", buf, 0)[0] != 0x0003:
        return
    off = struct.unpack_from("<H", buf, 2)[0]
    strings, resmap, depth = [], [], 0
    while off + 8 <= len(buf):
        ctype, hsize, csize = struct.unpack_from("<HHI", buf, off)
        if csize < 8:
            break
        if ctype == 0x0001:
            strings = arsc.read_pool(buf, off)
        elif ctype == 0x0180:
            n = (csize - hsize) // 4
            resmap = list(struct.unpack_from("<%dI" % n, buf, off + hsize))
        elif ctype == 0x0102:
            _ns, name, attr_start, attr_size, attr_count = struct.unpack_from("<IIHHH", buf, off + 16)
            attrs = []
            base = off + 16 + attr_start
            for i in range(attr_count):
                a_ns, a_name, a_raw, _sz, _r0, dtype, data = struct.unpack_from("<IIIHBBI", buf, base + i * attr_size)
                aid = resmap[a_name] if a_name < len(resmap) else 0
                aname = table.name(aid) if aid else (strings[a_name] if a_name < len(strings) else "?")
                if aid and aname == "?":
                    aname = "0x%08x" % aid
                if dtype == 0x03:
                    val = repr(strings[data]) if data < len(strings) else "str#%d" % data
                elif dtype in (0x01, 0x02):
                    n = table.name(data)
                    val = "%s%s" % (TYPE_NAMES[dtype], n if n != "?" else "0x%08x" % data)
                else:
                    val = arsc.fmt_value(dtype, data, strings)
                attrs.append((aname, aid, val))
            yield depth, strings[name] if name < len(strings) else "?", attrs
            depth += 1
        elif ctype == 0x0103:
            depth -= 1
        off += csize


def dump(apk, rid):
    buf = apk.layout_bytes(rid)
    if not buf:
        print("0x%08x %s: sem bytes" % (rid, apk.table.name(rid)))
        return
    print("0x%08x %s (%d bytes)" % (rid, apk.table.name(rid), len(buf)))
    for depth, tag, attrs in parse(buf, apk.table):
        print("%s<%s" % ("  " * depth, tag))
        for name, _aid, val in attrs:
            print("%s    %s = %s" % ("  " * depth, name.replace("attr/", ""), val))


def main():
    if len(sys.argv) < 4:
        sys.exit(__doc__)
    apk = Apk(sys.argv[1])
    cmd, arg = sys.argv[2], sys.argv[3]
    if cmd == "dump":
        if arg.startswith("0x"):
            dump(apk, int(arg, 16))
        else:
            for rid, name in apk.layouts():
                if name == arg:
                    dump(apk, rid)
    elif cmd == "with-id":
        needle = struct.pack("<I", int(arg, 16))
        limit = int(sys.argv[4]) if len(sys.argv) > 4 else 3
        for rid, _name in apk.layouts():
            buf = apk.layout_bytes(rid)
            if buf and needle in buf:
                dump(apk, rid)
                limit -= 1
                if limit <= 0:
                    break
    elif cmd == "find-attr":
        want = int(arg, 16)
        for rid, name in apk.layouts():
            buf = apk.layout_bytes(rid)
            if not buf or struct.pack("<I", want) not in buf:
                continue
            for _depth, tag, attrs in parse(buf, apk.table):
                for _aname, aid, val in attrs:
                    if aid == want:
                        print("0x%08x %-50s <%s> = %s" % (rid, name, tag.split(".")[-1], val))
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
