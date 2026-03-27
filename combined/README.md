# Nicket Uttarwar — Portfolio

Bare-bones static portfolio: multi-page (Home, About, Experience, **Nicket's Life**, Art, Contact). Responsive layout.

**Stack:** HTML and CSS only. No JavaScript, no frameworks, no fonts or scripts. Single stylesheet (`css/style.css`). Content and images only.

---

## Hosting on Ubuntu

### 1. System update

```bash
sudo apt update && sudo apt upgrade -y
```

---

### 2. Clone the repo

```bash
sudo mkdir -p /var/www
sudo chown $USER:$USER /var/www
cd /var/www
git clone https://github.com/<your-username>/nicketuttarwar.com.git nicketuttarwar.com
cd nicketuttarwar.com
```

Ensure these exist and are readable by the web server:

- `index.html` (home)
- `404.html` (not-found page; use **root-absolute** paths like `/css/…`, `/images/…`)
- `about/index.html`, `experience/index.html`, `life/index.html`, `art/index.html`, `contact/index.html`
- `css/style.css`, `js/portfolio-images.js`, `images/` (logo and page assets)

**Heritage section (About page)** — optional images in `images/` for the Naturell explainer. If missing, placeholders show. Add any you have:
- `heritage-intro.jpg` — roots / where I come from
- `naturell-logo.jpg` — Naturell India branding
- `naturell-max-protein.jpg` — Max Protein / RiteBite bars
- `naturell-building.jpg` — building the company
- `zydus-wellness.jpg` — Zydus Wellness (e.g. logo or HQ)

---

### 3. Nginx

**Install Nginx**

```bash
sudo apt install nginx -y
```

**Create site config**

```bash
sudo nano /etc/nginx/sites-available/nicketuttarwar.com
```

Paste:

```nginx
server {
    listen 80;
    server_name nicketuttarwar.com www.nicketuttarwar.com;
    root /var/www/nicketuttarwar.com;
    index index.html;

    error_page 404 /404.html;
    location = /404.html {
        root /var/www/nicketuttarwar.com;
    }

    location / {
        try_files $uri $uri/ $uri/index.html =404;
    }

    location ~* \.(css|js|png|jpg|jpeg|gif|ico|svg|webp|pdf)$ {
        expires 7d;
        add_header Cache-Control "public, immutable";
    }
}
```

**Enable the site and reload Nginx**

```bash
sudo ln -s /etc/nginx/sites-available/nicketuttarwar.com /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

**Optional: HTTPS with Let’s Encrypt**

```bash
sudo apt install certbot python3-certbot-nginx -y
sudo certbot --nginx -d nicketuttarwar.com -d www.nicketuttarwar.com
```

Certbot will adjust the Nginx config for SSL. Renewal is automatic.

---

### 4. Check that it works

- **https://nicketuttarwar.com** (or http before SSL) → home page
- **https://nicketuttarwar.com/about/** → About page
- **https://nicketuttarwar.com/experience/**, **/life/**, **/art/**, **/contact/** → other pages

If you see 404 for paths like `/about/`, the server isn’t serving `index.html` for directories. With the config above, Nginx will serve `.../about/index.html` for `/about/`.

Unknown paths should return **your** `404.html` (not a plain Nginx page). After adding the `error_page` and `location = /404.html` blocks above, reload Nginx and open a bogus URL (e.g. `/this-does-not-exist`) to confirm.

---

## Hosting on AWS (S3 + CloudFront)

This repo’s Terraform deploys **`combined/`** to the **bucket root** (e.g. `aws s3 sync combined/ s3://YOUR_BUCKET/ --delete`). Object keys mirror the folder layout: **`about/index.html`** for **`/about/`**, **`404.html`** at the root for errors, etc.

**How routing works:** CloudFront uses the bucket’s **S3 static website** hostname (`…s3-website-…amazonaws.com`) as its **origin**, not the S3 **REST** API. The website endpoint honors **index** and **error** documents (`index.html`, `404.html`), so URLs like **`https://www.example.com/about/`** resolve to **`about/index.html`**. The REST API alone cannot do that without edge rewrites.

**Tradeoffs:** The website origin requires **public read** access to objects (`s3:GetObject` for `arn:aws:s3:::bucket/*`). **Origin Access Control** only applies to the REST API. Visitors should use your **custom domain** (CloudFront); direct S3 URLs can still fetch public objects if the key is known.

**Terraform also configures** CloudFront **custom error responses** (403/404 → **`/404.html`**) as a fallback. **Paths in `404.html`** stay **root-absolute** (`/css/style.css`, `/images/…`) so the error page renders for bad URLs under any path.

See the repository **`README.md`** for deployment steps, **`terraform/`** for the exact resources, and **`./scripts/tf-output.sh`** for **`s3_website_endpoint`** and **`cloudfront_domain_name`**.

---

## Local preview (no server)

```bash
cd /path/to/nicketuttarwar.com
python3 -m http.server 8080
```

Then open **http://localhost:8080**. Use **http://localhost:8080/about/** etc. for inner pages.

**404 page:** Python’s `http.server` does **not** map missing URLs to `404.html`; open **http://localhost:8080/404.html** directly to preview the not-found page. Use Nginx or CloudFront to get automatic custom 404s for bad URLs.

**Quick sanity check** (with the server running): `python3 test_site.py` — verifies all pages and main assets return 200.

---

## Project layout

```
nicketuttarwar.com/
├── index.html
├── 404.html                # Not found (root-absolute asset paths)
├── about/index.html
├── experience/index.html
├── art/index.html
├── contact/index.html
├── life/index.html
├── uttarwarart/            # Interactive art portfolio (same site: /uttarwarart/ on nicketuttarwar.com)
├── css/style.css
├── js/portfolio-images.js  # Portfolio pages only
├── images/                 # Logo and page assets
├── test_site.py            # Optional: run with server to verify all pages load
└── README.md
```

---

## Notes

- **Stack:** HTML and CSS; portfolio pages include a small `js/portfolio-images.js` helper. **Uttarwar Art** (`uttarwarart/`) uses JavaScript and Three.js. Mobile menu uses a CSS-only checkbox pattern.
- **No build step:** deploy the repo as-is.
- **Contact:** The contact page uses a `mailto:` link only; there is no server-side form.
- **Paths:** Inner pages use `../` for assets (e.g. `../css/style.css`). Keep the folder structure.
- **Images:** All image assets live in `images/`. Subpages use `../images/...`.
- **HTTPS:** On a VPS, use Certbot (steps above). On AWS, TLS terminates at **CloudFront** (ACM); see the repo **`README.md`**.
