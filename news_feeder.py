# ~/news_feeder_app/news_feeder.py

import feedparser
import requests
import smtplib
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
import datetime
import os
import sys
from urllib.parse import urlparse
from sqlalchemy import create_engine, Column, Integer, String, Text, DateTime
from sqlalchemy.orm import sessionmaker
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.exc import IntegrityError

import config # Your custom config file

# --- Database Setup ---
# DATABASE_FILE is relative to the script's location
DATABASE_FILE = os.path.join(os.path.dirname(__file__), "data", "news_archive.db")
DATABASE_URL = f"sqlite:///{DATABASE_FILE}"

Base = declarative_base()

class NewsArticle(Base):
    __tablename__ = 'articles'
    id = Column(Integer, primary_key=True)
    source = Column(String(255), nullable=False)
    title = Column(String(500), nullable=False)
    link = Column(String(1000), unique=True, nullable=False)
    summary = Column(Text)
    published_date = Column(DateTime)
    fetched_date = Column(DateTime, default=datetime.datetime.now)

    def __repr__(self):
        return f"<NewsArticle(title='{self.title[:50]}...', source='{self.source}')>"

def init_db():
    engine = create_engine(DATABASE_URL)
    Base.metadata.create_all(engine)
    return sessionmaker(bind=engine)()

# --- Utility Functions ---
def validate_url(url):
    try:
        result = urlparse(url)
        return all([result.scheme, result.netloc])
    except ValueError:
        return False

def get_base_html_structure(title, is_index_page=False):
    """
    Returns the common HTML structure including responsive meta tag,
    Inter font, and dark mode styles and toggle for both index and digest pages.
    """
    toggle_button = """
    <button id="theme-toggle" class="theme-toggle">
        <span class="icon-light" role="img" aria-label="Light Mode">&#9728;</span>
        <span class="icon-dark" role="img" aria-label="Dark Mode">&#9790;</span>
    </button>
    """ # Always include toggle button now

    # Modified JavaScript for default dark mode
    script_toggle = """
    <script>
      const toggleBtn = document.getElementById('theme-toggle');
      const currentTheme = localStorage.getItem('theme');

      if (currentTheme) {
        document.documentElement.setAttribute('data-theme', currentTheme);
      } else {
        // Default to dark mode if no preference saved or system preference is not explicitly light
        document.documentElement.setAttribute('data-theme', 'dark');
        localStorage.setItem('theme', 'dark');
      }

      toggleBtn.addEventListener('click', () => {
        let theme = document.documentElement.getAttribute('data-theme');
        if (theme === 'dark') {
          document.documentElement.setAttribute('data-theme', 'light');
          localStorage.setItem('theme', 'light');
        } else {
          document.documentElement.setAttribute('data-theme', 'dark');
          localStorage.setItem('theme', 'dark');
        }
      });
    </script>
    """ 

    html_head = f"""<!DOCTYPE html>
<html>
<head>
<meta charset='utf-8'>
<meta name='viewport' content='width=device-width, initial-scale=1.0'>
<title>{title}</title>
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;600;700&display=swap" rel="stylesheet">
<style>
  :root {{
    --background-light: #f9fafb;
    --text-light: #1f2937;
    --card-bg-light: #ffffff;
    --border-light: #e5e7eb;
    --primary-light: #2563eb;
    --header-bg-light: #dbeafe; /* Lighter blue for header in light mode */
  }}

  [data-theme='dark'] {{
    --background-light: #111827;
    --text-light: #e5e7eb;
    --card-bg-light: #1f2937;
    --border-light: #374151;
    --primary-light: #60a5fa;
    --header-bg-light: #1f2937; /* Darker blue for header in dark mode */
  }}

  body {{
    font-family: 'Inter', sans-serif;
    line-height: 1.6;
    margin: 0;
    padding: 0;
    background-color: var(--background-light);
    color: var(--text-light);
    transition: background-color 0.3s ease, color 0.3s ease;
  }}
  .container {{
    max-width: 900px;
    margin: 20px auto;
    padding: 20px;
    background-color: var(--background-light);
    border-radius: 8px;
    box-shadow: 0 4px 12px rgba(0,0,0,0.08);
    transition: background-color 0.3s ease, box-shadow 0.3s ease;
  }}
  @media (max-width: 768px) {{
    .container {{
      margin: 10px;
      padding: 15px;
      border-radius: 0;
      box-shadow: none;
    }}
  }}
  h1 {{
    color: var(--primary-light);
    border-bottom: 2px solid var(--primary-light);
    padding-bottom: 15px;
    margin-bottom: 30px;
    font-size: 2.2em;
    font-weight: 700;
  }}
  h2 {{
    color: var(--primary-light);
    margin-top: 35px;
    border-bottom: 1px dashed var(--border-light);
    padding-bottom: 10px;
    font-size: 1.6em;
    font-weight: 600;
  }}
  ul {{
    list-style: none;
    padding: 0;
  }}
  li {{
    background-color: var(--card-bg-light);
    border: 1px solid var(--border-light);
    margin-bottom: 15px;
    padding: 20px;
    border-radius: 8px;
    box-shadow: 0 2px 8px rgba(0,0,0,0.05);
    transition: background-color 0.3s ease, border-color 0.3s ease, box-shadow 0.3s ease;
  }}
  li:hover {{
    box-shadow: 0 4px 16px rgba(0,0,0,0.1);
  }}
  a {{
    color: var(--primary-light);
    text-decoration: none;
    font-weight: 600;
  }}
  a:hover {{
    text-decoration: underline;
  }}
  p {{
    margin-top: 10px;
    color: var(--text-light);
  }}
  .footer {{
    text-align: center;
    margin-top: 50px;
    font-size: 0.85em;
    color: #777;
    padding-top: 20px;
    border-top: 1px solid var(--border-light);
  }}
  .theme-toggle {{
    position: fixed;
    top: 20px;
    right: 20px;
    background-color: var(--card-bg-light);
    color: var(--primary-light);
    border: 1px solid var(--border-light);
    border-radius: 50%;
    width: 40px;
    height: 40px;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 1.5em;
    cursor: pointer;
    box-shadow: 0 2px 8px rgba(0,0,0,0.1);
    transition: background-color 0.3s ease, color 0.3s ease, border-color 0.3s ease, box-shadow 0.3s ease;
    z-index: 1000;
  }}
  .theme-toggle:hover {{
    background-color: var(--primary-light);
    color: var(--card-bg-light);
  }}
  /* Hide one icon based on theme */
  [data-theme='light'] .icon-dark {{ display: none; }}
  [data-theme='dark'] .icon-light {{ display: none; }}
</style>
</head>
<body>
  <div class="container">
    {toggle_button}
"""
    return html_head, script_toggle

def fetch_and_format_news(session):
    """
    Fetches news from configured RSS feeds, stores unique articles in DB,
    and formats recent articles into an HTML string for the daily digest.
    """
    today_date_str = datetime.date.today().strftime("%d %B, %Y")
    page_title = f"UPSC Daily News Digest - {today_date_str}"
    html_head, script_toggle = get_base_html_structure(page_title, is_index_page=False)
    
    formatted_html_content = html_head + f"<h1>{page_title}</h1>"
    
    fetched_article_count = 0

    for source, url in config.RSS_FEEDS.items():
        if not validate_url(url):
            print(f"Skipping invalid URL for {source}: {url}")
            continue

        print(f"Fetching news from {source}...")
        try:
            feed = feedparser.parse(url)
        except Exception as e:
            print(f"Error parsing feed for {source}: {e}")
            continue

        if not feed.entries:
            print(f"No new entries found for {source}.")
            continue

        source_new_articles_count = 0
        for entry in feed.entries:
            title = entry.title if hasattr(entry, 'title') else 'No Title'
            link = entry.link if hasattr(entry, 'link') else '#'
            summary = entry.get('summary', entry.get('description', 'No summary available.'))
            summary = summary.replace('&lt;p&gt;', '').replace('&lt;/p&gt;', '').replace('&amp;', '&')

            published = datetime.datetime.now()
            if hasattr(entry, 'published_parsed') and entry.published_parsed:
                try:
                    published = datetime.datetime(*entry.published_parsed[:6])
                except ValueError:
                    pass

            existing_article = session.query(NewsArticle).filter_by(link=link).first()
            if not existing_article:
                new_article = NewsArticle(
                    source=source,
                    title=title,
                    link=link,
                    summary=summary,
                    published_date=published,
                    fetched_date=datetime.datetime.now()
                )
                session.add(new_article)
                try:
                    session.commit()
                    source_new_articles_count += 1
                    fetched_article_count += 1
                except IntegrityError:
                    session.rollback()
                except Exception as e:
                    session.rollback()
                    print(f"  Error saving article {title[:50]}...: {e}")

        if source_new_articles_count > 0:
            print(f"Fetched {source_new_articles_count} new articles for {source}.")

    today_start = datetime.datetime.now().replace(hour=0, minute=0, second=0, microsecond=0)
    recent_articles_for_digest = session.query(NewsArticle)\
        .filter(NewsArticle.fetched_date >= today_start)\
        .order_by(NewsArticle.fetched_date.desc())\
        .all()
    
    articles_by_source = {}
    for article in recent_articles_for_digest:
        if article.source not in articles_by_source:
            articles_by_source[article.source] = []
        articles_by_source[article.source].append(article)
    
    if not articles_by_source:
        formatted_html_content += "<p>No new articles fetched today.</p>"
    else:
        for source_name in sorted(articles_by_source.keys()):
            formatted_html_content += f"<h2>{source_name}</h2>"
            formatted_html_content += "<ul>"
            for article in articles_by_source[source_name][:config.ARTICLES_PER_FEED]:
                formatted_html_content += f"<li><a href='{article.link}'><strong>{article.title}</strong></a><br><p>{article.summary}</p></li>"
            formatted_html_content += "</ul>"

    formatted_html_content += "<div class='footer'>Generated by your UPSC Daily News Feeder.</div>\n</div>\n" + script_toggle + "\n</body>\n</html>"
    return formatted_html_content

def send_to_webhook(content_html):
    if not config.WEBHOOK_URL or not config.ENABLE_WEBHOOK_DELIVERY:
        print("Webhook delivery not configured or disabled. Skipping.")
        return

    payload = {
        "content": f"UPSC Daily Digest is ready for {datetime.date.today().strftime('%d %B, %Y')}! Check your email/GitHub Pages."
    }
    try:
        response = requests.post(config.WEBHOOK_URL, json=payload)
        response.raise_for_status()
        print("Webhook notification sent successfully.")
    except requests.exceptions.RequestException as e:
        print(f"Failed to send webhook notification: {e}")

def send_email(html_content):
    if not config.ENABLE_EMAIL_DELIVERY or not all([config.SENDER_EMAIL, config.SENDER_PASSWORD, config.RECIPIENT_EMAIL]):
        print("Email delivery not configured or disabled. Skipping.")
        return

    msg = MIMEMultipart('alternative')
    msg['Subject'] = f"UPSC Daily News Digest - {datetime.date.today().strftime('%d %B, %Y')}"
    msg['From'] = config.SENDER_EMAIL
    msg['To'] = config.RECIPIENT_EMAIL

    msg.attach(MIMEText(html_content, 'html'))

    try:
        with smtplib.SMTP(config.SMTP_SERVER, config.SMTP_PORT) as server:
            server.starttls()
            server.login(config.SENDER_EMAIL, config.SENDER_PASSWORD)
            server.send_message(msg)
            print("Email sent successfully!")
    except Exception as e:
        print(f"Failed to send email: {e}")

def save_digest_to_file(html_content, base_dir="docs"):
    """
    Saves the daily digest HTML to a dated file and updates an index.html.
    This prepares the files for GitHub Pages.
    """
    output_dir = os.path.join(os.path.dirname(__file__), base_dir)
    os.makedirs(output_dir, exist_ok=True) # Ensure the directory exists

    date_filename = datetime.date.today().strftime("%Y-%m-%d_daily_digest.html")
    full_path = os.path.join(output_dir, date_filename)

    try:
        with open(full_path, 'w', encoding='utf-8') as f:
            f.write(html_content)
        print(f"Daily digest saved to: {full_path}")

        # Update index.html to list all digests
        digests = sorted([f for f in os.listdir(output_dir) if f.endswith('_daily_digest.html')], reverse=True)
        
        index_page_title = "UPSC Daily News Digests Archive"
        index_html_head, _ = get_base_html_structure(index_page_title, is_index_page=True) # Pass is_index_page=True for index.html
        
        index_html_content = index_html_head + f"<h1>{index_page_title}</h1>\n    <ul>\n"
        
        for digest_file in digests:
            display_date = digest_file.replace('_daily_digest.html', '').replace('-', ' ').strip().replace(' ', '-')
            index_html_content += f"        <li><a href='./{digest_file}'>Daily Digest for {display_date}</a></li>\n"
        
        index_html_content += "    </ul>\n</div>\n</body>\n</html>"

        with open(os.path.join(output_dir, 'index.html'), 'w', encoding='utf-8') as f:
            f.write(index_html_content)
        print("index.html updated.")

    except Exception as e:
        print(f"Error saving daily digest or updating index.html: {e}")


if __name__ == "__main__":
    print("Starting UPSC Daily News Digest generation...")
    session = init_db()

    try:
        formatted_news = fetch_and_format_news(session)
        
        # Save to file for GitHub Pages
        save_digest_to_file(formatted_news)

        if config.ENABLE_EMAIL_DELIVERY:
            send_email(formatted_news)
        else:
            print("Email delivery is disabled in config.")

        if config.ENABLE_WEBHOOK_DELIVERY:
            # You might want to pass the GitHub Pages URL here once known
            send_to_webhook(formatted_news) 
        else:
            print("Webhook delivery is disabled in config.")
    except Exception as e:
        print(f"An error occurred during main execution: {e}")
        session.rollback()
    finally:
        session.close()
        print("News digest generation complete.")

