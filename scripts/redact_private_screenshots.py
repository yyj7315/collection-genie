from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parent.parent
ARTIFACTS = ROOT / "artifacts"
FONT_PATH = Path(r"C:\Windows\Fonts\msyh.ttc")


def load_font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    try:
        return ImageFont.truetype(str(FONT_PATH), size)
    except OSError:
        return ImageFont.load_default()


def redact_author(image: Image.Image) -> Image.Image:
    assert image.size == (1316, 2832)
    result = image.convert("RGB")
    draw = ImageDraw.Draw(result)
    background = result.getpixel((25, 700))
    draw.rounded_rectangle((44, 640, 510, 770), radius=18, fill=background)
    draw.text((64, 674), "作者信息已隐藏", fill="#6E7F79", font=load_font(30))
    return result


def redact_share_panel(image: Image.Image) -> Image.Image:
    assert image.size == (1316, 2832)
    result = image.convert("RGB")
    draw = ImageDraw.Draw(result)

    # Cover the creator handle above the share sheet.
    handle_background = result.getpixel((600, 330))
    draw.rounded_rectangle((44, 290, 520, 395), radius=18, fill=handle_background)
    draw.text((64, 324), "作者信息已隐藏", fill="#F4F8F7", font=load_font(28))

    # Replace the full shared-content text preview with a neutral placeholder.
    draw.rounded_rectangle((286, 1148, 1250, 1396), radius=20, fill="#FFFFFF")
    preview_text = "分享内容预览已隐藏"
    preview_font = load_font(28)
    preview_box = draw.textbbox((0, 0), preview_text, font=preview_font)
    draw.text(
        (286 + (964 - (preview_box[2] - preview_box[0])) // 2, 1242),
        preview_text,
        fill="#6E7F79",
        font=preview_font,
    )

    # Cover all recommended contact avatars and names while retaining the app choices.
    draw.rounded_rectangle((0, 1590, 1316, 1955), radius=28, fill="#EEF3F1")
    placeholder = "联系人姓名和头像已隐藏"
    font = load_font(28)
    text_box = draw.textbbox((0, 0), placeholder, font=font)
    text_width = text_box[2] - text_box[0]
    draw.text(
        ((result.width - text_width) // 2, 1732),
        placeholder,
        fill="#6E7F79",
        font=font,
    )
    return result


def save_without_metadata(image: Image.Image, path: Path) -> None:
    image.save(path, format="JPEG", quality=95, optimize=True)


def main() -> None:
    share_panel = ARTIFACTS / "final-share-panel.jpeg"
    detail = ARTIFACTS / "detail-updated-v5.jpeg"
    open_original = ARTIFACTS / "open-original.jpeg"

    save_without_metadata(
        redact_share_panel(Image.open(share_panel)),
        share_panel,
    )
    save_without_metadata(
        redact_author(Image.open(detail)),
        detail,
    )
    save_without_metadata(
        redact_author(Image.open(open_original)),
        open_original,
    )

    print("Redacted:", share_panel)
    print("Redacted:", detail)
    print("Redacted:", open_original)


if __name__ == "__main__":
    main()
