#!/usr/bin/env python3
import os
import shutil
import subprocess
from PIL import Image, ImageDraw, ImageFont

WIDTH = 760
HEIGHT = 420

BG_COLOR = (26, 26, 32)
TITLEBAR_BG = (36, 36, 44)
TAB_ACTIVE_BG = (26, 26, 32)
TAB_INACTIVE_BG = (32, 32, 38)
GUTTER_BG = (32, 32, 38)
GUTTER_FG = (100, 110, 125)
BORDER_COLOR = (50, 50, 60)
TEXT_COLOR = (225, 230, 240)
COMMENT_COLOR = (120, 135, 150)
KEYWORD_COLOR = (255, 123, 114)
STRING_COLOR = (165, 214, 255)
NUMBER_COLOR = (121, 192, 255)
ACCENT_BLUE = (56, 139, 253)
ACCENT_GREEN = (52, 199, 89)
SELECTION_BG = (40, 85, 140, 220)
BTN_BLUE = (0, 122, 255)

FONT_MONO = ImageFont.truetype("/System/Library/Fonts/Menlo.ttc", 14)
FONT_MONO_BOLD = ImageFont.truetype("/System/Library/Fonts/Menlo.ttc", 14)
FONT_UI = ImageFont.truetype("/System/Library/Fonts/AppleSDGothicNeo.ttc", 12)
FONT_UI_BOLD = ImageFont.truetype("/System/Library/Fonts/AppleSDGothicNeo.ttc", 13)
FONT_TITLE = ImageFont.truetype("/System/Library/Fonts/AppleSDGothicNeo.ttc", 12)
FONT_BADGE = ImageFont.truetype("/System/Library/Fonts/AppleSDGothicNeo.ttc", 12)
FONT_BADGE_BOLD = ImageFont.truetype("/System/Library/Fonts/AppleSDGothicNeo.ttc", 13)
FONT_MODAL_TITLE = ImageFont.truetype("/System/Library/Fonts/AppleSDGothicNeo.ttc", 13)

def draw_window_base(draw, title="Notepad++ - config.env", tab_name="config.env"):
    draw.rectangle([(0, 0), (WIDTH, HEIGHT)], fill=BG_COLOR)
    draw.rectangle([(0, 0), (WIDTH, 36)], fill=TITLEBAR_BG)
    draw.line([(0, 36), (WIDTH, 36)], fill=BORDER_COLOR, width=1)
    
    # Traffic lights
    draw.ellipse([(14, 12), (24, 22)], fill=(255, 95, 86))
    draw.ellipse([(32, 12), (42, 22)], fill=(255, 189, 46))
    draw.ellipse([(50, 12), (60, 22)], fill=(39, 201, 63))
    
    # Active Tab
    tab_w = 130
    draw.rectangle([(75, 6), (75 + tab_w, 36)], fill=TAB_ACTIVE_BG)
    draw.line([(75, 6), (75 + tab_w, 6)], fill=ACCENT_BLUE, width=2)
    draw.line([(75, 6), (75, 36)], fill=BORDER_COLOR, width=1)
    draw.line([(75 + tab_w, 6), (75 + tab_w, 36)], fill=BORDER_COLOR, width=1)
    draw.text((90, 13), tab_name, fill=TEXT_COLOR, font=FONT_TITLE)
    draw.text((75 + tab_w - 16, 13), "×", fill=(140, 140, 150), font=FONT_TITLE)
    
    # Inactive Tab
    draw.rectangle([(75 + tab_w, 6), (75 + tab_w * 2, 36)], fill=TAB_INACTIVE_BG)
    draw.line([(75 + tab_w * 2, 6), (75 + tab_w * 2, 36)], fill=BORDER_COLOR, width=1)
    draw.text((75 + tab_w + 16, 13), "main.py", fill=(120, 125, 135), font=FONT_TITLE)
    
    # Window title centered
    title_box = draw.textbbox((0, 0), title, font=FONT_TITLE)
    title_w = title_box[2] - title_box[0]
    draw.text(((WIDTH - title_w) // 2 + 50, 11), title, fill=(140, 145, 155), font=FONT_TITLE)
    
    # Gutter
    gutter_w = 48
    draw.rectangle([(0, 37), (gutter_w, HEIGHT - 22)], fill=GUTTER_BG)
    draw.line([(gutter_w, 37), (gutter_w, HEIGHT - 22)], fill=BORDER_COLOR, width=1)
    
    # Status bar
    draw.rectangle([(0, HEIGHT - 22), (WIDTH, HEIGHT)], fill=TITLEBAR_BG)
    draw.line([(0, HEIGHT - 22), (WIDTH, HEIGHT - 22)], fill=BORDER_COLOR, width=1)
    draw.text((12, HEIGHT - 17), "UTF-8", fill=(150, 155, 165), font=FONT_TITLE)
    draw.text((65, HEIGHT - 17), "Unix (LF)", fill=(150, 155, 165), font=FONT_TITLE)
    draw.text((130, HEIGHT - 17), "INS", fill=(150, 155, 165), font=FONT_TITLE)
    draw.text((WIDTH - 210, HEIGHT - 17), "Ln 1, Col 1  |  Column Mode", fill=ACCENT_BLUE, font=FONT_TITLE)

def draw_gutter_numbers(draw, total_lines=9, active_range=(1, 6)):
    y_start = 50
    line_h = 27
    for i in range(1, total_lines + 1):
        y = y_start + (i - 1) * line_h
        color = ACCENT_BLUE if (active_range and active_range[0] <= i <= active_range[1]) else GUTTER_FG
        num_str = str(i)
        num_box = draw.textbbox((0, 0), num_str, font=FONT_MONO)
        num_w = num_box[2] - num_box[0]
        draw.text((36 - num_w, y), num_str, fill=color, font=FONT_MONO)

def draw_badge(img, text, subtext=None, key_combo=None, border_color=ACCENT_BLUE):
    draw = ImageDraw.Draw(img, "RGBA")
    badge_w = 340
    badge_h = 52 if subtext else 38
    bx = WIDTH - badge_w - 16
    by = 46
    
    draw.rounded_rectangle([(bx, by), (bx + badge_w, by + badge_h)], radius=6, fill=(18, 20, 26, 240), outline=border_color, width=1)
    
    tx = bx + 14
    if key_combo:
        kw = draw.textbbox((0, 0), key_combo, font=FONT_BADGE_BOLD)[2] - draw.textbbox((0, 0), key_combo, font=FONT_BADGE_BOLD)[0] + 14
        draw.rounded_rectangle([(bx + 10, by + 8), (bx + 10 + kw, by + 28)], radius=4, fill=(45, 60, 85, 255), outline=(90, 120, 160), width=1)
        draw.text((bx + 17, by + 10), key_combo, fill=(255, 255, 255), font=FONT_BADGE_BOLD)
        tx = bx + 18 + kw

    draw.text((tx, by + 10), text, fill=(255, 255, 255), font=FONT_BADGE_BOLD)
    if subtext:
        draw.text((bx + 14, by + 32), subtext, fill=(175, 195, 220), font=FONT_UI)

def draw_mouse_cursor(draw, x, y, label=None):
    # Draw simple macOS style pointer
    pts = [(x, y), (x, y + 15), (x + 4, y + 12), (x + 8, y + 18), (x + 11, y + 16), (x + 7, y + 10), (x + 12, y + 10)]
    draw.polygon(pts, fill=(255, 255, 255), outline=(0, 0, 0))
    if label:
        draw.rounded_rectangle([(x + 16, y - 2), (x + 16 + len(label) * 8 + 10, y + 16)], radius=3, fill=(0, 122, 255, 220))
        draw.text((x + 21, y), label, fill=(255, 255, 255), font=FONT_TITLE)


# ==========================================
# 1. GENERATE COLUMN MODE GIF
# ==========================================
def generate_column_mode_gif():
    frames = []
    tmp_dir = "/tmp/npp_gif_colmode"
    os.makedirs(tmp_dir, exist_ok=True)
    
    base_lines = [
        "PORT = 8080",
        'HOST = "127.0.0.1"',
        'DB_NAME = "production"',
        "TIMEOUT = 30",
        "MAX_CONN = 100",
        'LOG_LEVEL = "debug"',
        "",
        "# Server configuration"
    ]
    
    y_start = 50
    line_h = 27
    x_code = 60
    char_w = 8.4 # approximate monospace char width for Menlo 14
    
    type_str = "export APP_"
    total_frames = 34
    
    for f in range(total_frames):
        img = Image.new("RGBA", (WIDTH, HEIGHT), BG_COLOR)
        draw = ImageDraw.Draw(img)
        draw_window_base(draw, title="Notepad++ - config.env", tab_name="config.env")
        
        # State logic
        # Frame 0-4: Normal view
        # Frame 5-11: Option+Drag selection
        # Frame 12-25: Multi-caret typing
        # Frame 26-33: Complete result pause
        
        active_lines = (1, 6) if f >= 5 else None
        draw_gutter_numbers(draw, total_lines=8, active_range=active_lines)
        
        current_type_len = 0
        if 12 <= f <= 24:
            current_type_len = int(((f - 12) / 12) * len(type_str))
        elif f > 24:
            current_type_len = len(type_str)
            
        typed_part = type_str[:current_type_len]
        
        # Draw code lines
        for i, line in enumerate(base_lines):
            y = y_start + i * line_h
            if i < 6:
                if f < 12:
                    # Original line
                    draw.text((x_code, y), line, fill=TEXT_COLOR, font=FONT_MONO)
                else:
                    # Line with typed prefix
                    full_line = typed_part + line
                    # Highlight typed part
                    draw.text((x_code, y), typed_part, fill=ACCENT_GREEN if f > 24 else (100, 210, 255), font=FONT_MONO_BOLD)
                    draw.text((x_code + current_type_len * char_w, y), line, fill=TEXT_COLOR, font=FONT_MONO)
            else:
                draw.text((x_code, y), line, fill=COMMENT_COLOR if line.startswith("#") else TEXT_COLOR, font=FONT_MONO)
        
        # Phase 1: Idle
        if f < 5:
            draw_badge(img, "열 모드(Column Mode) 시작", "⌥ (Option) 키를 누른 채 마우스로 세로 드래그합니다", key_combo="⌥ + Drag")
            # Single caret on Line 1
            if (f % 2) == 0:
                draw.rectangle([(x_code, y_start + 2), (x_code + 2, y_start + 20)], fill=ACCENT_BLUE)
        
        # Phase 2: Selection drag
        elif 5 <= f < 12:
            drag_progress = (f - 5) / 6.0
            sel_lines = int(1 + drag_progress * 5)
            # Draw selection vertical stripe
            sel_y2 = y_start + sel_lines * line_h - 6
            draw.rectangle([(x_code - 2, y_start - 2), (x_code + 3, sel_y2)], fill=(56, 139, 253, 100), outline=ACCENT_BLUE)
            
            # Draw multi carets
            for li in range(sel_lines):
                cy = y_start + li * line_h
                draw.rectangle([(x_code, cy + 2), (x_code + 2, cy + 20)], fill=(100, 200, 255))
                
            mouse_y = y_start + drag_progress * 5 * line_h + 10
            draw_mouse_cursor(draw, x_code + 10, mouse_y, label="⌥ Option Drag")
            draw_badge(img, "다중 라인 사각형 영역 선택", "6개 라인에 다중 커서(Multi-Caret)가 동시 활성화되었습니다", key_combo="⌥ + Drag", border_color=ACCENT_BLUE)
            
        # Phase 3: Multi-caret typing
        elif 12 <= f <= 24:
            caret_x = x_code + current_type_len * char_w
            # Draw blinking multi-carets
            for li in range(6):
                cy = y_start + li * line_h
                draw.rectangle([(caret_x, cy + 2), (caret_x + 2, cy + 20)], fill=(120, 220, 255))
            draw_badge(img, "다중 커서 동시 입력 (Typing)", f"모든 라인에 '{typed_part}' 가 실시간 동시 입력됩니다", border_color=ACCENT_GREEN)
            
        # Phase 4: Done
        else:
            caret_x = x_code + len(type_str) * char_w
            if (f % 2) == 0:
                for li in range(6):
                    cy = y_start + li * line_h
                    draw.rectangle([(caret_x, cy + 2), (caret_x + 2, cy + 20)], fill=ACCENT_BLUE)
            draw_badge(img, "열 모드 일괄 수정 완료!", "수십 줄의 코드/설정도 단 몇 초만에 일괄 수정 가능합니다", border_color=ACCENT_BLUE)
            
        frame_path = f"{tmp_dir}/frame_{f:03d}.png"
        img.save(frame_path)
        frames.append(frame_path)
        
    out_gif = "docs/assets/column_mode.gif"
    subprocess.run([
        "ffmpeg", "-y", "-framerate", "9", "-i", f"{tmp_dir}/frame_%03d.png",
        "-vf", "split[s0][s1];[s0]palettegen=max_colors=128:reserve_transparent=0[p];[s1][p]paletteuse=dither=bayer:bayer_scale=3",
        out_gif
    ], check=True)
    
    shutil.copy(out_gif, "assets/column_mode.gif")
    shutil.copy(out_gif, "PowerEditor/src/assets/column_mode.gif")
    shutil.rmtree(tmp_dir)
    print(f"Generated {out_gif} successfully!")


# ==========================================
# 2. GENERATE COLUMN EDITOR GIF
# ==========================================
def generate_column_editor_gif():
    frames = []
    tmp_dir = "/tmp/npp_gif_coledit"
    os.makedirs(tmp_dir, exist_ok=True)
    
    raw_items = [
        ('item_', ' : "Apple",'),
        ('item_', ' : "Banana",'),
        ('item_', ' : "Orange",'),
        ('item_', ' : "Grape",'),
        ('item_', ' : "Strawberry",'),
        ('item_', ' : "Watermelon",'),
        ('', ''),
        ('// List of products', '')
    ]
    
    y_start = 50
    line_h = 27
    x_code = 60
    char_w = 8.4
    
    total_frames = 36
    
    for f in range(total_frames):
        img = Image.new("RGBA", (WIDTH, HEIGHT), BG_COLOR)
        draw = ImageDraw.Draw(img)
        draw_window_base(draw, title="Notepad++ - products.json", tab_name="products.json")
        
        # State timeline:
        # f 0-4: Selected column before opening dialog
        # f 5-9: Press ⌥⌘C shortcut (dialog pops up)
        # f 10-20: Dialog open with settings highlighted
        # f 21-24: Click OK button
        # f 25-35: Dialog closes, numbers 01, 02, 03... inserted with glowing effect!
        
        draw_gutter_numbers(draw, total_lines=8, active_range=(1, 6))
        
        # Draw code lines
        col_insert_x = x_code + len("item_") * char_w
        
        for i, (pfx, sfx) in enumerate(raw_items):
            y = y_start + i * line_h
            if i < 6:
                if f < 25:
                    # Original with selection
                    draw.text((x_code, y), pfx, fill=TEXT_COLOR, font=FONT_MONO)
                    draw.text((col_insert_x, y), sfx, fill=STRING_COLOR if '"' in sfx else TEXT_COLOR, font=FONT_MONO)
                    # Draw column selection line
                    draw.rectangle([(col_insert_x - 1, y + 2), (col_insert_x + 2, y + 20)], fill=(56, 139, 253, 180))
                else:
                    # Inserted numbers!
                    num_str = f"{i+1:02d}"
                    draw.text((x_code, y), pfx, fill=TEXT_COLOR, font=FONT_MONO)
                    draw.text((col_insert_x, y), num_str, fill=(255, 215, 0) if f < 30 else ACCENT_GREEN, font=FONT_MONO_BOLD)
                    draw.text((col_insert_x + 2 * char_w, y), sfx, fill=STRING_COLOR if '"' in sfx else TEXT_COLOR, font=FONT_MONO)
                    if (f % 2) == 0:
                        draw.rectangle([(col_insert_x + 2 * char_w, y + 2), (col_insert_x + 2 * char_w + 2, y + 20)], fill=ACCENT_BLUE)
            else:
                draw.text((x_code, y), pfx + sfx, fill=COMMENT_COLOR, font=FONT_MONO)
                
        # Phase 1: Column selected, ready to call dialog
        if f < 5:
            draw_badge(img, "열 편집기(Column Editor) 호출", "수정할 열을 선택 후 단축키 ⌥⌘C 를 누릅니다", key_combo="⌥⌘C")
            
        # Phase 2 & 3: Dialog open
        elif 5 <= f <= 24:
            # Draw semi-transparent modal overlay
            draw.rectangle([(0, 0), (WIDTH, HEIGHT)], fill=(0, 0, 0, 100))
            
            # Modal Dialog Box
            dw, dh = 360, 230
            dx = (WIDTH - dw) // 2
            dy = (HEIGHT - dh) // 2
            
            # Dialog body
            draw.rounded_rectangle([(dx, dy), (dx + dw, dy + dh)], radius=10, fill=(40, 42, 50, 255), outline=(75, 85, 105), width=2)
            # Dialog titlebar
            draw.rectangle([(dx, dy), (dx + dw, dy + 32)], fill=(48, 52, 62))
            draw.line([(dx, dy + 32), (dx + dw, dy + 32)], fill=(65, 70, 82), width=1)
            draw.text((dx + 16, dy + 8), "Column Editor / 열 편집기 (⌥⌘C)", fill=(255, 255, 255), font=FONT_MODAL_TITLE)
            
            # Radio options
            # Text to insert (Unchecked)
            draw.ellipse([(dx + 20, dy + 45), (dx + 30, dy + 55)], fill=(30, 32, 38), outline=(120, 130, 145))
            draw.text((dx + 36, dy + 44), "Text to Insert (텍스트 삽입)", fill=(180, 185, 195), font=FONT_UI)
            
            # Number to insert (Checked)
            draw.ellipse([(dx + 20, dy + 70), (dx + 30, dy + 80)], fill=(30, 32, 38), outline=ACCENT_BLUE)
            draw.ellipse([(dx + 23, dy + 73), (dx + 27, dy + 77)], fill=ACCENT_BLUE)
            draw.text((dx + 36, dy + 69), "Number to Insert (연속 번호 삽입)", fill=(255, 255, 255), font=FONT_UI_BOLD)
            
            # Inputs grid
            # Initial Number
            draw.text((dx + 36, dy + 96), "Initial number (시작 번호):", fill=(200, 205, 215), font=FONT_UI)
            draw.rounded_rectangle([(dx + 220, dy + 92), (dx + 330, dy + 114)], radius=4, fill=(24, 26, 32), outline=ACCENT_BLUE)
            draw.text((dx + 230, dy + 95), "1", fill=(255, 255, 255), font=FONT_MONO)
            
            # Increase by
            draw.text((dx + 36, dy + 124), "Increase by (증가치):", fill=(200, 205, 215), font=FONT_UI)
            draw.rounded_rectangle([(dx + 220, dy + 120), (dx + 330, dy + 142)], radius=4, fill=(24, 26, 32), outline=(70, 75, 90))
            draw.text((dx + 230, dy + 123), "1", fill=(255, 255, 255), font=FONT_MONO)
            
            # Format & Leading Zeros
            draw.text((dx + 36, dy + 152), "Format: (●) Dec   ( ) Hex", fill=(190, 200, 215), font=FONT_UI)
            
            # Checkbox Leading Zeros
            draw.rectangle([(dx + 200, dy + 151), (dx + 212, dy + 163)], fill=ACCENT_BLUE, outline=ACCENT_BLUE)
            draw.text((dx + 202, dy + 149), "✓", fill=(255, 255, 255), font=FONT_UI_BOLD)
            draw.text((dx + 218, dy + 151), "0 채우기 (01..)", fill=ACCENT_GREEN, font=FONT_UI_BOLD)
            
            # Buttons
            btn_ok_color = (0, 95, 210) if f >= 21 else (0, 122, 255)
            draw.rounded_rectangle([(dx + dw - 165, dy + dh - 40), (dx + dw - 95, dy + dh - 14)], radius=5, fill=btn_ok_color)
            draw.text((dx + dw - 148, dy + dh - 34), "확인 (OK)", fill=(255, 255, 255), font=FONT_UI_BOLD)
            
            draw.rounded_rectangle([(dx + dw - 85, dy + dh - 40), (dx + dw - 20, dy + dh - 14)], radius=5, fill=(60, 65, 78))
            draw.text((dx + dw - 72, dy + dh - 34), "취소", fill=(200, 205, 215), font=FONT_UI)
            
            if f < 21:
                draw_badge(img, "열 편집기 옵션 설정", "시작 번호: 1, 증가치: 1, [✓] 0 채우기 선택", key_combo="⌥⌘C")
            else:
                draw_mouse_cursor(draw, dx + dw - 130, dy + dh - 26)
                draw_badge(img, "확인 버튼 클릭", "선택된 옵션으로 일련번호 생성 명령 실행", border_color=ACCENT_GREEN)
                
        # Phase 4: Applied result
        else:
            draw_badge(img, "연속 번호 일괄 삽입 완료!", "01, 02, 03... 연속 번호가 모든 행에 깔끔하게 생성되었습니다", border_color=ACCENT_GREEN)
            
        frame_path = f"{tmp_dir}/frame_{f:03d}.png"
        img.save(frame_path)
        frames.append(frame_path)
        
    out_gif = "docs/assets/column_editor.gif"
    subprocess.run([
        "ffmpeg", "-y", "-framerate", "8", "-i", f"{tmp_dir}/frame_%03d.png",
        "-vf", "split[s0][s1];[s0]palettegen=max_colors=128:reserve_transparent=0[p];[s1][p]paletteuse=dither=bayer:bayer_scale=3",
        out_gif
    ], check=True)
    
    shutil.copy(out_gif, "assets/column_editor.gif")
    shutil.copy(out_gif, "PowerEditor/src/assets/column_editor.gif")
    shutil.rmtree(tmp_dir)
    print(f"Generated {out_gif} successfully!")

if __name__ == "__main__":
    generate_column_mode_gif()
    generate_column_editor_gif()
