#!/usr/bin/env python3
"""
Generate QA Test Report PDF with embedded screenshots.

Usage:
    python3 generate-qa-report.py <output_path> <json_data>

    json_data is a JSON string with this structure:
    {
      "title": "TRIDENT-822",
      "subtitle": "QA Test Report",
      "description": "Combined Funnel Authentication & Login Modal",
      "environment": "QA (qa.boattrader.com)",
      "date": "2026-03-06",
      "tests": [
        {
          "name": "Test 1: Login Modal Appears",
          "status": "PASS",
          "verify_items": [
            {"num": 1, "item": "Modal overlay appears", "status": "PASS", "details": "Dialog element present"},
            ...
          ],
          "screenshots": [
            {"path": "/absolute/path/to/screenshot.png", "caption": "Modal with blur"},
            ...
          ],
          "notes": "Optional notes about the test"
        },
        ...
      ]
    }
"""

import json
import os
import sys

try:
    from fpdf import FPDF
except ImportError:
    print("fpdf2 not installed. Installing...")
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "fpdf2", "-q"])
    from fpdf import FPDF


class QAReport(FPDF):
    def __init__(self, report_title="QA Test Report"):
        super().__init__()
        self.report_title = report_title

    def header(self):
        self.set_font("Helvetica", "B", 10)
        self.set_text_color(100, 100, 100)
        self.cell(0, 8, self.report_title, align="R", new_x="LMARGIN", new_y="NEXT")
        self.line(10, self.get_y(), 200, self.get_y())
        self.ln(4)

    def footer(self):
        self.set_y(-15)
        self.set_font("Helvetica", "I", 8)
        self.set_text_color(128, 128, 128)
        self.cell(0, 10, f"Page {self.page_no()}/{{nb}}", align="C")

    def section_title(self, title):
        self.set_font("Helvetica", "B", 14)
        self.set_text_color(30, 80, 160)
        self.cell(0, 10, title, new_x="LMARGIN", new_y="NEXT")
        self.ln(2)

    def sub_title(self, title):
        self.set_font("Helvetica", "B", 11)
        self.set_text_color(60, 60, 60)
        self.cell(0, 8, title, new_x="LMARGIN", new_y="NEXT")
        self.ln(1)

    def body_text(self, text):
        self.set_font("Helvetica", "", 10)
        self.set_text_color(40, 40, 40)
        self.multi_cell(0, 5.5, text)
        self.ln(2)

    def status_badge(self, status):
        if status == "PASS":
            self.set_fill_color(34, 139, 34)
        elif "PARTIAL" in status:
            self.set_fill_color(218, 165, 32)
        else:
            self.set_fill_color(220, 50, 50)
        self.set_font("Helvetica", "B", 10)
        self.set_text_color(255, 255, 255)
        w = self.get_string_width(status) + 10
        self.cell(w, 7, status, fill=True, align="C")
        self.set_text_color(40, 40, 40)
        self.ln(6)

    def add_screenshot(self, path, caption=""):
        if not os.path.exists(path):
            self.body_text(f"[Screenshot not found: {os.path.basename(path)}]")
            return
        if self.get_y() > 180:
            self.add_page()
        img_w = 170
        self.image(path, x=20, w=img_w)
        if caption:
            self.set_font("Helvetica", "I", 8)
            self.set_text_color(100, 100, 100)
            self.cell(0, 5, caption, align="C", new_x="LMARGIN", new_y="NEXT")
            self.set_text_color(40, 40, 40)
        self.ln(4)

    def verify_row(self, num, item, status, details=""):
        col = (34, 139, 34) if status == "PASS" else (218, 165, 32) if "PARTIAL" in status or "CODE" in status else (220, 50, 50) if "FAIL" in status or "NOT" in status else (218, 165, 32)
        self.set_x(15)
        self.set_font("Helvetica", "B", 9)
        self.set_text_color(*col)
        prefix = f"{num}. [{status}] "
        self.write(5.5, prefix)
        self.set_text_color(40, 40, 40)
        self.set_font("Helvetica", "", 9)
        self.multi_cell(0, 5.5, item)
        if details:
            self.set_x(20)
            self.set_font("Helvetica", "I", 8)
            self.set_text_color(100, 100, 100)
            self.multi_cell(0, 4.5, details)
            self.set_text_color(40, 40, 40)
        self.ln(1)


def generate_report(output_path, data):
    title = data.get("title", "QA Test Report")
    subtitle = data.get("subtitle", "Test Report")
    description = data.get("description", "")
    environment = data.get("environment", "QA")
    date = data.get("date", "")
    tests = data.get("tests", [])

    pdf = QAReport(f"{title} {subtitle}")
    pdf.alias_nb_pages()
    pdf.set_auto_page_break(auto=True, margin=20)
    pdf.add_page()

    # Title page
    pdf.set_font("Helvetica", "B", 22)
    pdf.set_text_color(30, 80, 160)
    pdf.ln(30)
    pdf.cell(0, 12, title, align="C", new_x="LMARGIN", new_y="NEXT")
    pdf.set_font("Helvetica", "B", 16)
    pdf.cell(0, 10, subtitle, align="C", new_x="LMARGIN", new_y="NEXT")
    pdf.ln(8)
    pdf.set_font("Helvetica", "", 11)
    pdf.set_text_color(80, 80, 80)
    if description:
        pdf.cell(0, 7, description, align="C", new_x="LMARGIN", new_y="NEXT")
    pdf.ln(10)
    if environment:
        pdf.cell(0, 7, f"Environment: {environment}", align="C", new_x="LMARGIN", new_y="NEXT")
    if date:
        pdf.cell(0, 7, f"Date: {date}", align="C", new_x="LMARGIN", new_y="NEXT")
    pdf.ln(20)

    # Summary table
    pdf.set_font("Helvetica", "B", 12)
    pdf.set_text_color(40, 40, 40)
    pdf.cell(0, 8, "Results Summary", align="C", new_x="LMARGIN", new_y="NEXT")
    pdf.ln(4)
    pdf.set_font("Helvetica", "", 10)

    pass_count = 0
    partial_count = 0
    fail_count = 0
    for test in tests:
        s = test.get("status", "UNKNOWN")
        col = (34, 139, 34) if s == "PASS" else (218, 165, 32) if "PARTIAL" in s else (220, 50, 50)
        pdf.cell(130, 7, test.get("name", ""))
        pdf.set_text_color(*col)
        pdf.set_font("Helvetica", "B", 10)
        pdf.cell(0, 7, s, new_x="LMARGIN", new_y="NEXT")
        pdf.set_text_color(40, 40, 40)
        pdf.set_font("Helvetica", "", 10)
        if s == "PASS":
            pass_count += 1
        elif "PARTIAL" in s:
            partial_count += 1
        else:
            fail_count += 1

    pdf.ln(4)
    total = len(tests)
    summary_parts = []
    if pass_count:
        summary_parts.append(f"{pass_count}/{total} fully passed")
    if partial_count:
        summary_parts.append(f"{partial_count}/{total} partially passed")
    if fail_count:
        summary_parts.append(f"{fail_count}/{total} failed")
    pdf.set_font("Helvetica", "B", 11)
    pdf.cell(0, 7, f"Overall: {', '.join(summary_parts)}", align="C", new_x="LMARGIN", new_y="NEXT")

    # Individual test pages
    for test in tests:
        pdf.add_page()
        pdf.section_title(test.get("name", "Test"))
        pdf.status_badge(test.get("status", "UNKNOWN"))
        pdf.ln(2)

        if test.get("notes"):
            pdf.body_text(test["notes"])

        for vi in test.get("verify_items", []):
            pdf.verify_row(
                vi.get("num", ""),
                vi.get("item", ""),
                vi.get("status", "UNKNOWN"),
                vi.get("details", ""),
            )

            # Check for screenshots that should appear after this verify item
            for ss in test.get("screenshots", []):
                if ss.get("after_item") == vi.get("num"):
                    pdf.ln(2)
                    pdf.sub_title(ss.get("caption", "Screenshot"))
                    pdf.add_screenshot(ss["path"], ss.get("caption", ""))

        # Add any screenshots not tied to specific verify items
        for ss in test.get("screenshots", []):
            if "after_item" not in ss:
                pdf.ln(2)
                pdf.sub_title(ss.get("caption", "Screenshot"))
                pdf.add_screenshot(ss["path"], ss.get("caption", ""))

    pdf.output(output_path)
    print(f"PDF generated: {output_path}")


def main():
    if len(sys.argv) < 3:
        print("Usage: python3 generate-qa-report.py <output_path> <json_file_path>")
        print("  json_file_path: path to a JSON file containing the report data")
        sys.exit(1)

    output_path = sys.argv[1]
    json_path = sys.argv[2]

    with open(json_path, "r") as f:
        data = json.load(f)

    generate_report(output_path, data)


if __name__ == "__main__":
    main()
