"""Exercise VHDL bitmap fetches and the actual RAM inspection port against captures."""
import hashlib
import json

from coretools import core_root
from run_baselines import run_case


def main():
    root=core_root()
    results=[run_case("video_bitmap",["rtl/rabbitpunch_bitmap.vhd","sim/board/bitmap_tb.sv"],
                      "bitmap_tb","40 ms","BITMAP_PASS")]
    fixtures=json.loads((root/"scripts/mame/video_fixtures.json").read_text(encoding="utf-8"))
    for item in fixtures:
        capture=root/item["capture"]
        name="bitmap_"+capture.name.replace("-","_")
        run_dir=root/"debug/baselines"/name
        run_dir.mkdir(parents=True,exist_ok=True)
        bitmap=(capture/"bitmap.bin").read_bytes()
        flags=int.from_bytes((capture/"reg_vregs.bin").read_bytes()[12:14],"big")
        (run_dir/"bitmap_words.hex").write_text("\n".join(bitmap[n:n+2].hex() for n in range(0,65536,2))+"\n",encoding="ascii")
        (run_dir/"video_flags.hex").write_text(f"{flags:04x}\n",encoding="ascii")
        expected=[]
        for y in range(216):
            for x in range(8,296):
                sx=(x+4)&511
                value=bitmap[y*256+sx//2]
                pen=(value>>4) if sx%2==0 else value&15
                index=512+((flags&15)<<4)+pen
                expected.append(f"{index|((pen!=15)<<10):03x}")
        (run_dir/"bitmap_expected.hex").write_text("\n".join(expected)+"\n",encoding="ascii")
        result=run_case(name,["rtl/rabbitpunch_layout.vhd","rtl/rabbitpunch_decode.vhd",
                        "rtl/rabbitpunch_ram16.vhd","rtl/rabbitpunch_board_memory.vhd", "rtl/rabbitpunch_memory.vhd","rtl/rabbitpunch_bitmap.vhd",
                        "sim/board/bitmap_capture_tb.sv"],"bitmap_capture_tb","20 ms","BITMAP_CAPTURE_PASS")
        result.update(set=item["set"],capture=item["capture"],pixels=62208,
                      bitmap_sha256=hashlib.sha256(bitmap).hexdigest(),flags=f"{flags:04x}")
        results.append(result)
    for result in results:
        result["log_sha256"]=hashlib.sha256((root/result["log"]).read_bytes()).hexdigest()
    (root/"docs/reference/bitmap_checks.json").write_text(json.dumps(results,indent=2)+"\n",encoding="utf-8")


if __name__=="__main__":main()
