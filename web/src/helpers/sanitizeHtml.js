/*
Copyright (C) 2025 Guangjitop

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as
published by the Free Software Foundation, either version 3 of the
License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU Affero General Public License for more details.

You should have received a copy of the GNU Affero General Public License
along with this program. If not, see <https://www.gnu.org/licenses/>.

For commercial licensing, please contact your-email@example.com
*/

const BLOCKED_TAGS = [
  'style',
  'script',
  'link',
  'meta',
  'base',
  'iframe',
  'object',
  'embed',
];

const URL_ATTRS = new Set(['href', 'src', 'xlink:href']);

export function sanitizeHtmlContent(rawHtml = '') {
  if (!rawHtml || typeof rawHtml !== 'string') {
    return '';
  }

  if (typeof window === 'undefined' || typeof window.DOMParser !== 'function') {
    return rawHtml;
  }

  const parser = new window.DOMParser();
  const doc = parser.parseFromString(rawHtml, 'text/html');
  const { body } = doc;

  if (!body) {
    return rawHtml;
  }

  body.querySelectorAll(BLOCKED_TAGS.join(',')).forEach((node) => node.remove());

  body.querySelectorAll('*').forEach((el) => {
    const attrs = Array.from(el.attributes || []);
    attrs.forEach((attr) => {
      const name = attr.name.toLowerCase();
      const value = (attr.value || '').trim();

      if (name.startsWith('on') || name === 'style' || name === 'srcdoc') {
        el.removeAttribute(attr.name);
        return;
      }

      if (URL_ATTRS.has(name) && /^javascript:/i.test(value)) {
        el.removeAttribute(attr.name);
      }
    });
  });

  return body.innerHTML;
}

