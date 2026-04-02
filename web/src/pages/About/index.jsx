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

import React, { useEffect, useState } from 'react';
import { API, showError } from '../../helpers';
import { marked } from 'marked';
import { Empty } from '@douyinfe/semi-ui';
import {
  IllustrationConstruction,
  IllustrationConstructionDark,
} from '@douyinfe/semi-illustrations';
import { useTranslation } from 'react-i18next';

const About = () => {
  const { t } = useTranslation();
  const [about, setAbout] = useState('');
  const [aboutLoaded, setAboutLoaded] = useState(false);
  const projectUrl = window.location.origin;
  const stripLegacyAboutNotice = (content = '') =>
    content
      .replace(/^.*One API v0\.5\.4.*(?:\r?\n)?/gim, '')
      .replace(/^.*AGPL v3\.0.*(?:\r?\n)?/gim, '')
      .trim();

  const displayAbout = async () => {
    const cachedAbout = localStorage.getItem('about') || '';
    if (cachedAbout && !cachedAbout.startsWith('https://')) {
      setAbout(stripLegacyAboutNotice(cachedAbout));
    } else {
      setAbout(cachedAbout);
    }
    const res = await API.get('/api/about');
    const { success, message, data } = res.data;
    if (success) {
      let aboutContent = data;
      if (!data.startsWith('https://')) {
        aboutContent = marked.parse(stripLegacyAboutNotice(data));
      }
      setAbout(aboutContent);
      localStorage.setItem('about', aboutContent);
    } else {
      showError(message);
      setAbout(t('加载关于内容失败...'));
    }
    setAboutLoaded(true);
  };

  useEffect(() => {
    displayAbout().then();
  }, []);

  const emptyStyle = {
    padding: '24px',
  };

  const customDescription = (
    <div style={{ textAlign: 'center' }}>
      <p>{t('可在设置页面设置关于内容，支持 HTML & Markdown')}</p>
      {t('项目地址：')}
      <a
        href={projectUrl}
        target='_blank'
        rel='noopener noreferrer'
        className='!text-semi-color-primary'
      >
        {projectUrl}
      </a>
    </div>
  );

  return (
    <div className='cyber-grid-bg min-h-screen text-cyber-text pt-[60px] px-4'>
      {aboutLoaded && about === '' ? (
        <div className='flex justify-center items-center h-screen p-8'>
          <Empty
            image={
              <IllustrationConstruction style={{ width: 150, height: 150 }} />
            }
            darkModeImage={
              <IllustrationConstructionDark
                style={{ width: 150, height: 150 }}
              />
            }
            description={t('管理员暂时未设置任何关于内容')}
            style={emptyStyle}
          >
            {customDescription}
          </Empty>
        </div>
      ) : (
        <>
          {about.startsWith('https://') ? (
            <iframe
              src={about}
              style={{ width: '100%', height: 'calc(100vh - 60px)', border: 'none' }}
            />
          ) : (
            <div className='max-w-4xl mx-auto py-12'>
              <div className='bg-black/40 cyber-chamfer border border-cyber-border backdrop-blur-md p-8'>
                <div
                  className='prose prose-lg prose-invert text-cyber-text max-w-none'
                  dangerouslySetInnerHTML={{ __html: about }}
                ></div>
              </div>
            </div>
          )}
        </>
      )}
    </div>
  );
};

export default About;
