enum WebpageExtraction {
    static let script = #"""
    const clean = value => (value || '').replace(/\s+/g, ' ').trim();
    const meta = selector => clean(document.querySelector(selector)?.getAttribute('content'));
    const documentTitle = clean(document.title);
    const findDate = object => {
        if (!object || typeof object !== 'object') return '';
        if (Array.isArray(object)) return object.map(findDate).find(Boolean) || '';
        return typeof object.datePublished === 'string' ? object.datePublished : findDate(object['@graph']);
    };
    let published = meta('meta[property="article:published_time"]');
    for (const script of document.querySelectorAll('script[type="application/ld+json"]')) {
        if (published) break;
        try { published = findDate(JSON.parse(script.textContent)); } catch (_) {}
    }
    const author = meta('meta[name="author"]') || meta('meta[property="article:author"]')
        || meta('meta[property="og:site_name"]') || location.hostname.replace(/^www\./, '');
    const text = clean(document.body?.innerText);
    const challenge = document.querySelector('#challenge-form, #challenge-running, #px-captcha')
        || /^(just a moment|attention required|one more step|ddos-guard)\b/i.test(documentTitle)
        || (text.length < 1500 && /checking your browser|verify you are human|enable javascript and cookies/i.test(text));
    if (challenge) return JSON.stringify({ blocked: true });
    const body = document.body?.cloneNode(true);
    if (!body) return JSON.stringify({ empty: true });
    body.querySelectorAll('script,style,nav,footer,aside,noscript,iframe,form,button,svg,template,dialog,' +
        '[hidden],[aria-hidden="true"],[role="navigation"],[role="banner"],[role="contentinfo"],' +
        '[role="dialog"],.site-navigation,.site-header,header:has(nav),.cookie-banner,.cookie-consent,' +
        '.advertisement,.ads,.social-share,.share-buttons')
        .forEach(node => node.remove());
    const score = node => {
        const length = clean(node.textContent).length;
        const links = [...node.querySelectorAll('a')].reduce((sum, link) => sum + clean(link.textContent).length, 0);
        return length - links * 0.5;
    };
    const largest = nodes => [...nodes].sort((a, b) => score(b) - score(a))[0];
    const semantic = largest(body.querySelectorAll('article')) || largest(body.querySelectorAll('main,[role="main"]'));
    const content = semantic || largest(body.querySelectorAll('section,div').length
        ? body.querySelectorAll('section,div') : [body]);
    const headline = clean(content.querySelector('h1')?.textContent);
    const title = (headline.length > 10 && documentTitle.toLowerCase().startsWith(headline.toLowerCase()))
        ? headline : meta('meta[property="og:title"]') || headline || documentTitle || location.hostname;
    for (const image of content.querySelectorAll('img')) {
        const source = image.getAttribute('data-src') || image.getAttribute('data-original');
        if (source && (!image.getAttribute('src') || image.getAttribute('src').startsWith('data:'))) {
            image.setAttribute('src', source);
        }
    }
    const maximumHTMLCharacters = 4 * 1024 * 1024;
    const html = content.outerHTML;
    if (html.length > maximumHTMLCharacters) return JSON.stringify({ tooLarge: true });
    return JSON.stringify({ title, author, published, html, baseURL: document.baseURI,
        readable: clean(content.textContent).length >= 80 });
    """#
}
