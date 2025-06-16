# ~/news_feeder_app/config.py

# --- RSS Feeds Configuration ---
# Dictionary where keys are source names and values are their RSS feed URLs.
# Only include feeds that you have confirmed are working reliably.
RSS_FEEDS = {
    "The Hindu - General Feeder": "https://www.thehindu.com/feeder/default.rss",
    "The Hindu - News Section": "https://www.thehindu.com/news/feeder/default.rss",
    "The Hindu - National News": "https://www.thehindu.com/news/national/feeder/default.rss",
    "The Hindu - Opinion Columns": "https://www.thehindu.com/opinion/columns/feeder/default.rss",
    "The Hindu - Editorials": "https://www.thehindu.com/opinion/editorial/feeder/default.rss",
    "The Hindu - Interviews": "https://www.thehindu.com/opinion/interview/feeder/default.rss",
    "The Hindu - Open Page": "https://www.thehindu.com/opinion/open-page/feeder/default.rss",
    "The Hindu - Reader's Editor": "https://www.thehindu.com/opinion/Readers-Editor/feeder/default.rss",
    "The Hindu - Business Budget": "https://www.thehindu.com/business/budget/feeder/default.rss",
    "The Hindu - Sport": "https://www.thehindu.com/sport/feeder/default.rss",
    "The Hindu - Entertainment": "https://www.thehindu.com/entertainment/feeder/default.rss",
    "The Hindu - Sci-Tech (Science)": "https://www.thehindu.com/sci-tech/science/feeder/default.rss",

    "Indian Express - All News": "https://indianexpress.com/feed/",
    "Indian Express - India News": "https://indianexpress.com/section/india/feed/",
    "Indian Express - Explained": "https://indianexpress.com/section/explained/feed/",
    "Indian Express - Opinion": "https://indianexpress.com/section/opinion/feed/",
    "Indian Express - Political Pulse": "https://indianexpress.com/section/political-pulse/feed/",

    "PIB - All Releases (English)": "https://pib.gov.in/AllRelease.aspx?PRID=1"
}

# --- Digest Formatting ---
# Number of articles to include per feed in the daily HTML digest.
ARTICLES_PER_FEED = 10 # You can adjust this number

# --- Email Delivery (DISABLED) ---
# Set to False to disable email notifications.
ENABLE_EMAIL_DELIVERY = False
SENDER_EMAIL = ""
SENDER_PASSWORD = ""
RECIPIENT_EMAIL = ""
SMTP_SERVER = ""
SMTP_PORT = 587 # Common TLS port

# --- Webhook Delivery (DISABLED by default) ---
# Set to True to enable webhook notifications (e.g., to Discord, Slack).
ENABLE_WEBHOOK_DELIVERY = False
WEBHOOK_URL = "" # Replace with your webhook URL if enabling.
