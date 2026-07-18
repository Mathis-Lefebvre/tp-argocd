import os
import re

def convert_markdown_to_html(md_path, html_out_path):
    with open(md_path, 'r', encoding='utf-8') as f:
        content = f.read()

    # Parsing basique de markdown pour le rapport
    html_content = ""
    lines = content.split('\n')
    in_list = False
    in_code = False
    in_table = False
    table_headers = []

    for line in lines:
        # Code block
        if line.strip().startswith('```'):
            if in_code:
                html_content += "</pre></div>\n"
                in_code = False
            else:
                lang = line.strip()[3:]
                html_content += f'<div class="code-wrapper"><pre class="language-{lang}">'
                in_code = True
            continue

        if in_code:
            # Sécuriser les chevrons HTML dans le code
            escaped = line.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')
            html_content += escaped + '\n'
            continue

        # Tables
        if line.strip().startswith('|'):
            cells = [c.strip() for c in line.split('|')[1:-1]]
            if not in_table:
                in_table = True
                html_content += "<table>\n<thead>\n<tr>\n"
                for cell in cells:
                    html_content += f"<th>{cell}</th>\n"
                html_content += "</tr>\n</thead>\n<tbody>\n"
                table_headers = cells
                continue
            else:
                if line.strip().startswith('|:-') or line.strip().startswith('| :--'):
                    # Ligne de séparation de header, on l'ignore
                    continue
                html_content += "<tr>\n"
                for cell in cells:
                    html_content += f"<td>{cell}</td>\n"
                html_content += "</tr>\n"
            continue
        else:
            if in_table:
                html_content += "</tbody>\n</table>\n"
                in_table = False

        # Titres
        if line.startswith('# '):
            html_content += f"<h1>{line[2:]}</h1>\n"
            continue
        elif line.startswith('## '):
            html_content += f"<h2>{line[3:]}</h2>\n"
            continue
        elif line.startswith('### '):
            html_content += f"<h3>{line[4:]}</h3>\n"
            continue

        # Liste à puces
        if line.strip().startswith('* ') or line.strip().startswith('- '):
            bullet = line.strip()[2:]
            # Formater les bold dans la liste
            bullet = re.sub(r'\*\*(.*?)\*\*', r'<strong>\1</strong>', bullet)
            bullet = re.sub(r'`(.*?)`', r'<code>\1</code>', bullet)
            if not in_list:
                html_content += "<ul>\n"
                in_list = True
            html_content += f"<li>{bullet}</li>\n"
            continue
        else:
            if in_list:
                html_content += "</ul>\n"
                in_list = False

        # Liste ordonnée
        match_ol = re.match(r'^\d+\.\s(.*)', line.strip())
        if match_ol:
            item_text = match_ol.group(1)
            item_text = re.sub(r'\*\*(.*?)\*\*', r'<strong>\1</strong>', item_text)
            item_text = re.sub(r'`(.*?)`', r'<code>\1</code>', item_text)
            html_content += f"<ol start='{re.match(r'^\\d+', line.strip())}'><li>{item_text}</li></ol>\n"
            continue

        # Ligne horizontale
        if line.strip() == '---':
            html_content += "<hr />\n"
            continue

        # Images
        img_match = re.match(r'^!\[(.*?)\]\((.*?)\)', line.strip())
        if img_match:
            alt = img_match.group(1)
            src = img_match.group(2)
            # Utiliser le chemin absolu pour le moteur de rendu PDF
            abs_src = os.path.abspath(src).replace('\\', '/')
            html_content += f'<div class="img-container"><img src="file:///{abs_src}" alt="{alt}"/><div class="caption">{alt}</div></div>\n'
            continue

        # Paragraphes normaux
        if line.strip():
            # Formater le gras, le code en ligne
            formatted = re.sub(r'\*\*(.*?)\*\*', r'<strong>\1</strong>', line)
            formatted = re.sub(r'`(.*?)`', r'<code>\1</code>', formatted)
            formatted = formatted.replace('✅', '<span class="status-badge success">✅</span>')
            formatted = formatted.replace('❌', '<span class="status-badge danger">❌</span>')
            formatted = formatted.replace('⚠️', '<span class="status-badge warning">⚠️</span>')
            html_content += f"<p>{formatted}</p>\n"

    # Style HTML Premium pour le Rapport PDF
    style = """
    <style>
        @import url('https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&family=JetBrains+Mono:wght@400;500&display=swap');
        
        body {
            font-family: 'Inter', sans-serif;
            color: #1e293b;
            background-color: #ffffff;
            line-height: 1.6;
            max-width: 850px;
            margin: 0 auto;
            padding: 40px 30px;
        }

        h1 {
            font-size: 32px;
            font-weight: 700;
            color: #0f172a;
            border-bottom: 2px solid #e2e8f0;
            padding-bottom: 10px;
            margin-top: 40px;
            margin-bottom: 20px;
        }

        h2 {
            font-size: 22px;
            font-weight: 600;
            color: #1e293b;
            margin-top: 30px;
            margin-bottom: 15px;
        }

        h3 {
            font-size: 18px;
            font-weight: 600;
            color: #334155;
            margin-top: 20px;
        }

        p {
            font-size: 15px;
            margin-bottom: 15px;
            text-align: justify;
        }

        ul, ol {
            margin-bottom: 20px;
            padding-left: 25px;
        }

        li {
            font-size: 15px;
            margin-bottom: 8px;
        }

        code {
            font-family: 'JetBrains Mono', monospace;
            background-color: #f1f5f9;
            color: #0f172a;
            padding: 2px 6px;
            border-radius: 4px;
            font-size: 14px;
        }

        .code-wrapper {
            background-color: #0f172a;
            border-radius: 8px;
            padding: 15px;
            margin: 20px 0;
            overflow-x: auto;
        }

        pre {
            font-family: 'JetBrains Mono', monospace;
            color: #e2e8f0;
            font-size: 13.5px;
            margin: 0;
            line-height: 1.5;
        }

        table {
            width: 100%;
            border-collapse: collapse;
            margin: 25px 0;
            font-size: 14.5px;
        }

        th {
            background-color: #f8fafc;
            color: #334155;
            font-weight: 600;
            text-align: left;
            border-bottom: 2px solid #cbd5e1;
            padding: 12px;
        }

        td {
            border-bottom: 1px solid #e2e8f0;
            padding: 10px 12px;
            color: #475569;
        }

        tr:nth-child(even) td {
            background-color: #f8fafc;
        }

        hr {
            border: 0;
            height: 1px;
            background: #e2e8f0;
            margin: 40px 0;
        }

        .status-badge {
            font-style: normal;
        }

        .img-container {
            margin: 30px 0;
            text-align: center;
            border: 1px solid #e2e8f0;
            border-radius: 8px;
            padding: 10px;
            background-color: #f8fafc;
            page-break-inside: avoid;
        }

        .img-container img {
            max-width: 100%;
            height: auto;
            border-radius: 6px;
            box-shadow: 0 4px 6px -1px rgb(0 0 0 / 0.05);
        }

        .caption {
            font-size: 13px;
            color: #64748b;
            margin-top: 10px;
            font-style: italic;
        }

        /* En-tête de page de garde */
        .header-section {
            text-align: center;
            margin-bottom: 50px;
            padding: 40px 0;
            background: linear-gradient(135deg, #0f172a 0%, #1e293b 100%);
            color: #ffffff;
            border-radius: 12px;
        }

        .header-section h1 {
            color: #ffffff;
            border-bottom: none;
            margin-top: 10px;
            font-size: 28px;
        }
        
        .header-metadata {
            color: #94a3b8;
            font-size: 14px;
            margin-top: 15px;
        }
    </style>
    """

    # Assembler le fichier HTML final
    header_html = """
    <!DOCTYPE html>
    <html lang="fr">
    <head>
        <meta charset="UTF-8">
        <title>Rapport de TP - GitOps & ArgoCD</title>
        {style}
    </head>
    <body>
        <div class="header-section">
            <h1>Compte-rendu de TP — GitOps & ArgoCD (DevHub Campus)</h1>
            <div class="header-metadata">
                <strong>5ESGI SRC</strong> &nbsp;|&nbsp; Étudiants : Mathis Lefebvre & Evan Lefevre
            </div>
        </div>
    """.format(style=style)

    footer_html = """
    </body>
    </html>
    """

    final_html = header_html + html_content + footer_html
    
    # Écriture du fichier HTML final
    with open(html_out_path, 'w', encoding='utf-8') as f:
        f.write(final_html)
    print(f"HTML généré à: {html_out_path}")

if __name__ == "__main__":
    convert_markdown_to_html("RAPPORT.md", "RAPPORT.html")
