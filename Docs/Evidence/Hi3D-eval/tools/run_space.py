"""Call townbox/hi3d10-zerogpu: `generate <image> <res> <outdir>` or `refine <image> <mesh> <res> <outdir>`."""
import json
import shutil
import sys
import time
from pathlib import Path

from gradio_client import Client, handle_file
from huggingface_hub import get_token

SPACE = "townbox/hi3d10-zerogpu"


def main() -> None:
    mode = sys.argv[1]
    client = Client(SPACE, token=get_token(), verbose=False)
    t0 = time.time()
    if mode == "generate":
        image, res, out = sys.argv[2], int(sys.argv[3]), Path(sys.argv[4])
        refined, coarse, _inp, info = client.predict(
            handle_file(image), res, 25, 0, True, api_name="/generate"
        )
        files = {"hi3d_refined.glb": refined, "coarse_hunyuan.glb": coarse}
    else:
        image, mesh, res, out = sys.argv[2], sys.argv[3], int(sys.argv[4]), Path(sys.argv[5])
        refined, _inp, info = client.predict(
            handle_file(image), handle_file(mesh), res, 25, 0, True, api_name="/refine"
        )
        files = {"hi3d_refined.glb": refined}
    out.mkdir(parents=True, exist_ok=True)
    for name, src in files.items():
        shutil.copy(src, out / name)
    info = info if isinstance(info, dict) else json.loads(info)
    info["client_wall_s"] = round(time.time() - t0, 1)
    (out / "info.json").write_text(json.dumps(info, indent=2))
    print(json.dumps(info))


if __name__ == "__main__":
    main()
