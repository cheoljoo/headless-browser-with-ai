#!/usr/bin/env python3
"""화면 캡처(PNG) + 설명(JSON)을 묶어서 HTML 리포트 메일로 보낸다.

사내 SMTP 릴레이(lgekrhqmh01.lge.com:25, 인증 불필요)를 그대로 사용한다는 점에서
~/code/ccr/sendmail.py 를 참고해 만들었다.

사용법:
    ./scripts/send_screenshot_report.py --manifest report.json --to someone@lge.com \
        --subject "제목" [--sender cheoljoo.lee@lge.com] [--test]

manifest(JSON) 형식:
{
  "intro": "리포트 맨 위에 들어갈 소개 문구(선택)",
  "items": [
    {"image": "/절대/경로/screenshot1.png", "title": "화면 제목", "seen": "무엇을 눌러서 나온 화면인지", "desc": "그 내용에 대한 해설"},
    ...
  ]
}
"""
import argparse
import json
import mimetypes
import os
import smtplib
from email.mime.image import MIMEImage
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText

SMTP_HOST = "lgekrhqmh01.lge.com"
SMTP_PORT = 25


def build_html(manifest):
    parts = []
    intro = manifest.get("intro")
    if intro:
        parts.append(f"<p>{intro}</p><hr>")

    for idx, item in enumerate(manifest["items"], start=1):
        cid = f"shot{idx}"
        title = item.get("title", f"화면 {idx}")
        seen = item.get("seen", "")
        desc = item.get("desc", "")
        parts.append(
            f"<h3>{idx}. {title}</h3>"
            f'<img src="cid:{cid}" width="600"><br>'
            f"<p><b>본 것:</b> {seen}</p>"
            f"<p><b>해설:</b> {desc}</p><hr>"
        )
    return "\n".join(parts)


def send_report(manifest_path, to_addrs, subject, sender, test=False):
    with open(manifest_path, "r", encoding="utf-8") as f:
        manifest = json.load(f)

    html = build_html(manifest)

    message = MIMEMultipart("related")
    message["Subject"] = subject
    message["From"] = sender
    message["To"] = ", ".join(to_addrs)

    message.attach(MIMEText(html, "html", "utf-8"))

    for idx, item in enumerate(manifest["items"], start=1):
        img_path = item["image"]
        if not os.path.exists(img_path):
            raise FileNotFoundError(img_path)
        mime_type, _ = mimetypes.guess_type(img_path)
        subtype = (mime_type or "image/png").split("/")[-1]
        with open(img_path, "rb") as imgf:
            mime_img = MIMEImage(imgf.read(), _subtype=subtype)
        mime_img.add_header("Content-ID", f"<shot{idx}>")
        mime_img.add_header("Content-Disposition", "inline", filename=os.path.basename(img_path))
        message.attach(mime_img)

    if test:
        print(f"[TEST] send to {to_addrs} from {sender} subject={subject!r}, "
              f"{len(manifest['items'])} images, html body {len(html)} chars")
        return

    with smtplib.SMTP(SMTP_HOST, SMTP_PORT) as server:
        server.sendmail(sender, to_addrs, message.as_string())
        server.quit()
    print(f"메일 발송 완료: {to_addrs}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="화면 캡처 + 설명 JSON을 HTML 리포트 메일로 발송")
    parser.add_argument("--manifest", required=True, help="report manifest JSON 경로")
    parser.add_argument("--to", required=True, nargs="+", help="받는 사람 이메일(들)")
    parser.add_argument("--subject", required=True, help="메일 제목")
    parser.add_argument("--sender", default="cheoljoo.lee@lge.com", help="보내는 사람 (기본: cheoljoo.lee@lge.com)")
    parser.add_argument("--test", action="store_true", help="실제 발송하지 않고 확인만")
    args = parser.parse_args()

    send_report(args.manifest, args.to, args.subject, args.sender, test=args.test)
