import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';

const DATABASE_NAME: string = 'collection_genie.db';
const TABLE_NAME: string = 'collections';

const CREATE_TABLE_SQL: string = `
CREATE TABLE IF NOT EXISTS collections (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  source TEXT NOT NULL,
  source_item_id TEXT NOT NULL DEFAULT '',
  original_url TEXT NOT NULL,
  canonical_url TEXT NOT NULL,
  title TEXT NOT NULL,
  author TEXT NOT NULL DEFAULT '',
  cover_url TEXT NOT NULL DEFAULT '',
  category TEXT NOT NULL,
  tags TEXT NOT NULL DEFAULT '',
  summary TEXT NOT NULL DEFAULT '',
  status TEXT NOT NULL DEFAULT '未看',
  collect_time INTEGER NOT NULL,
  last_opened_time INTEGER NOT NULL DEFAULT 0,
  open_count INTEGER NOT NULL DEFAULT 0,
  share_count INTEGER NOT NULL DEFAULT 1,
  notes TEXT NOT NULL DEFAULT ''
)`;

export interface CollectionItem {
  id: number;
  source: string;
  source_item_id: string;
  original_url: string;
  canonical_url: string;
  title: string;
  author: string;
  cover_url: string;
  category: string;
  tags: string;
  summary: string;
  status: string;
  collect_time: number;
  last_opened_time: number;
  open_count: number;
  share_count: number;
  notes: string;
}

export interface AddCollectionResult {
  created: boolean;
  category: string;
  item: CollectionItem;
}

interface ParsedShare {
  source: string;
  sourceItemId: string;
  originalUrl: string;
  canonicalUrl: string;
  title: string;
  author: string;
  category: string;
  tags: string;
  summary: string;
}

interface TitleUpdate {
  id: number;
  title: string;
}

interface SourceUpdate {
  id: number;
  source: string;
  sourceItemId: string;
  canonicalUrl: string;
  tags: string;
}

export class CollectionRepository {
  private static instance: CollectionRepository | null = null;
  private store: relationalStore.RdbStore | null = null;
  private initialized: boolean = false;

  static getInstance(): CollectionRepository {
    if (CollectionRepository.instance === null) {
      CollectionRepository.instance = new CollectionRepository();
    }
    return CollectionRepository.instance;
  }

  async initialize(context: common.Context): Promise<void> {
    if (this.initialized && this.store !== null) {
      return;
    }
    const config: relationalStore.StoreConfig = {
      name: DATABASE_NAME,
      securityLevel: relationalStore.SecurityLevel.S1
    };
    this.store = await relationalStore.getRdbStore(context, config);
    await this.store.executeSql(CREATE_TABLE_SQL);
    await this.normalizeStoredTitles();
    await this.normalizeStoredSources();
    this.initialized = true;
  }

  async addFromShare(payload: string): Promise<AddCollectionResult> {
    const parsed = this.parseShare(payload);
    let existing = await this.findByCanonicalUrl(parsed.canonicalUrl);
    if (existing === null) {
      existing = await this.findBySourceAndTitle(parsed.source, parsed.title);
    }
    if (existing !== null) {
      const values: relationalStore.ValuesBucket = {
        'share_count': existing.share_count + 1,
        'title': existing.title.length > 0 ? existing.title : parsed.title,
        'summary': existing.summary.length > 0 ? existing.summary : parsed.summary
      };
      const predicates = new relationalStore.RdbPredicates(TABLE_NAME);
      predicates.equalTo('id', existing.id);
      await this.requireStore().update(values, predicates);
      existing.share_count += 1;
      return {
        created: false,
        category: existing.category,
        item: existing
      };
    }

    const values: relationalStore.ValuesBucket = {
      'source': parsed.source,
      'source_item_id': parsed.sourceItemId,
      'original_url': parsed.originalUrl,
      'canonical_url': parsed.canonicalUrl,
      'title': parsed.title,
      'author': parsed.author,
      'cover_url': '',
      'category': parsed.category,
      'tags': parsed.tags,
      'summary': parsed.summary,
      'status': '未看',
      'collect_time': Date.now(),
      'last_opened_time': 0,
      'open_count': 0,
      'share_count': 1,
      'notes': ''
    };
    const rowId = await this.requireStore().insert(TABLE_NAME, values);
    const inserted = await this.findById(rowId);
    if (inserted === null) {
      throw new Error('收藏保存后未能读取记录。');
    }
    return {
      created: true,
      category: parsed.category,
      item: inserted
    };
  }

  async getAll(): Promise<CollectionItem[]> {
    const resultSet = await this.requireStore().querySql(
      'SELECT * FROM collections ORDER BY collect_time DESC'
    );
    const items: CollectionItem[] = [];
    while (resultSet.goToNextRow()) {
      items.push(this.readItem(resultSet));
    }
    resultSet.close();
    return items;
  }

  async findById(id: number): Promise<CollectionItem | null> {
    const resultSet = await this.requireStore().querySql(
      'SELECT * FROM collections WHERE id = ? LIMIT 1',
      [id]
    );
    let item: CollectionItem | null = null;
    if (resultSet.goToNextRow()) {
      item = this.readItem(resultSet);
    }
    resultSet.close();
    return item;
  }

  async updateStatus(id: number, status: string): Promise<void> {
    const values: relationalStore.ValuesBucket = {
      'status': status
    };
    const predicates = new relationalStore.RdbPredicates(TABLE_NAME);
    predicates.equalTo('id', id);
    await this.requireStore().update(values, predicates);
  }

  async updateCategory(id: number, category: string): Promise<void> {
    const values: relationalStore.ValuesBucket = {
      'category': category
    };
    const predicates = new relationalStore.RdbPredicates(TABLE_NAME);
    predicates.equalTo('id', id);
    await this.requireStore().update(values, predicates);
  }

  async updateNotes(id: number, notes: string): Promise<void> {
    const values: relationalStore.ValuesBucket = {
      'notes': notes
    };
    const predicates = new relationalStore.RdbPredicates(TABLE_NAME);
    predicates.equalTo('id', id);
    await this.requireStore().update(values, predicates);
  }

  async recordOpen(id: number): Promise<void> {
    await this.requireStore().executeSql(
      'UPDATE collections SET open_count = open_count + 1, last_opened_time = ?, ' +
      'status = CASE WHEN status = ? THEN ? ELSE status END WHERE id = ?',
      [Date.now(), '未看', '在看', id]
    );
  }

  async deleteById(id: number): Promise<void> {
    const predicates = new relationalStore.RdbPredicates(TABLE_NAME);
    predicates.equalTo('id', id);
    await this.requireStore().delete(predicates);
  }

  private requireStore(): relationalStore.RdbStore {
    if (this.store === null) {
      throw new Error('收藏数据库尚未初始化。');
    }
    return this.store;
  }

  private async findByCanonicalUrl(url: string): Promise<CollectionItem | null> {
    const resultSet = await this.requireStore().querySql(
      'SELECT * FROM collections WHERE canonical_url = ? LIMIT 1',
      [url]
    );
    let item: CollectionItem | null = null;
    if (resultSet.goToNextRow()) {
      item = this.readItem(resultSet);
    }
    resultSet.close();
    return item;
  }

  private async findBySourceAndTitle(source: string, title: string): Promise<CollectionItem | null> {
    const normalizedTitle = title.trim();
    if (normalizedTitle.length === 0) {
      return null;
    }
    const resultSet = await this.requireStore().querySql(
      'SELECT * FROM collections WHERE source = ? AND title = ? LIMIT 1',
      [source, normalizedTitle]
    );
    let item: CollectionItem | null = null;
    if (resultSet.goToNextRow()) {
      item = this.readItem(resultSet);
    }
    resultSet.close();
    return item;
  }

  private async normalizeStoredTitles(): Promise<void> {
    const resultSet = await this.requireStore().querySql(
      'SELECT id, title, summary FROM collections'
    );
    const updates: TitleUpdate[] = [];
    while (resultSet.goToNextRow()) {
      const id = resultSet.getLong(resultSet.getColumnIndex('id'));
      const title = resultSet.getString(resultSet.getColumnIndex('title'));
      const cleaned = this.cleanTitle(title);
      if (cleaned.length > 0 && cleaned !== title) {
        updates.push({ id: id, title: cleaned });
      }
    }
    resultSet.close();
    for (let index = 0; index < updates.length; index++) {
      const row = updates[index];
      await this.requireStore().executeSql(
        'UPDATE collections SET title = ?, summary = ? WHERE id = ?',
        [row.title, row.title, row.id]
      );
    }
  }

  private async normalizeStoredSources(): Promise<void> {
    const resultSet = await this.requireStore().querySql(
      'SELECT id, source, source_item_id, original_url, canonical_url, tags FROM collections'
    );
    const updates: SourceUpdate[] = [];
    while (resultSet.goToNextRow()) {
      const id = resultSet.getLong(resultSet.getColumnIndex('id'));
      const currentSource = resultSet.getString(resultSet.getColumnIndex('source'));
      const currentSourceItemId = resultSet.getString(resultSet.getColumnIndex('source_item_id'));
      const originalUrl = resultSet.getString(resultSet.getColumnIndex('original_url'));
      const currentCanonicalUrl = resultSet.getString(resultSet.getColumnIndex('canonical_url'));
      const currentTags = resultSet.getString(resultSet.getColumnIndex('tags'));
      const detectedSource = this.detectSource(originalUrl);
      if (detectedSource.length === 0) {
        continue;
      }
      const sourceItemId = this.extractSourceItemId(originalUrl, detectedSource);
      const canonicalUrl = this.toCanonicalUrl(originalUrl, detectedSource, sourceItemId);
      const tags = this.replacePlatformTag(currentTags, detectedSource);
      if (currentSource !== detectedSource ||
        currentSourceItemId !== sourceItemId ||
        currentCanonicalUrl !== canonicalUrl ||
        currentTags !== tags) {
        updates.push({
          id: id,
          source: detectedSource,
          sourceItemId: sourceItemId,
          canonicalUrl: canonicalUrl,
          tags: tags
        });
      }
    }
    resultSet.close();
    for (let index = 0; index < updates.length; index++) {
      const row = updates[index];
      await this.requireStore().executeSql(
        'UPDATE collections SET source = ?, source_item_id = ?, canonical_url = ?, tags = ? WHERE id = ?',
        [row.source, row.sourceItemId, row.canonicalUrl, row.tags, row.id]
      );
    }
  }

  private readItem(resultSet: relationalStore.ResultSet): CollectionItem {
    return {
      id: resultSet.getLong(resultSet.getColumnIndex('id')),
      source: resultSet.getString(resultSet.getColumnIndex('source')),
      source_item_id: resultSet.getString(resultSet.getColumnIndex('source_item_id')),
      original_url: resultSet.getString(resultSet.getColumnIndex('original_url')),
      canonical_url: resultSet.getString(resultSet.getColumnIndex('canonical_url')),
      title: resultSet.getString(resultSet.getColumnIndex('title')),
      author: resultSet.getString(resultSet.getColumnIndex('author')),
      cover_url: resultSet.getString(resultSet.getColumnIndex('cover_url')),
      category: resultSet.getString(resultSet.getColumnIndex('category')),
      tags: resultSet.getString(resultSet.getColumnIndex('tags')),
      summary: resultSet.getString(resultSet.getColumnIndex('summary')),
      status: resultSet.getString(resultSet.getColumnIndex('status')),
      collect_time: resultSet.getLong(resultSet.getColumnIndex('collect_time')),
      last_opened_time: resultSet.getLong(resultSet.getColumnIndex('last_opened_time')),
      open_count: resultSet.getLong(resultSet.getColumnIndex('open_count')),
      share_count: resultSet.getLong(resultSet.getColumnIndex('share_count')),
      notes: resultSet.getString(resultSet.getColumnIndex('notes'))
    };
  }

  private parseShare(payload: string): ParsedShare {
    const urlMatch: RegExpMatchArray | null = payload.match(/https?:\/\/[^\s，。！？]+/i);
    const originalUrl = urlMatch === null ? '' : this.trimUrl(urlMatch[0]);
    const detectedSource = this.detectSource(originalUrl);
    const source = detectedSource.length > 0 ? detectedSource : '其他来源';
    const titlePart = originalUrl.length > 0 ? payload.substring(0, payload.indexOf(originalUrl)) : payload;
    const cleanedTitle = this.cleanTitle(titlePart);
    const sourceItemId = this.extractSourceItemId(originalUrl, source);
    const canonicalUrl = originalUrl.length > 0
      ? this.toCanonicalUrl(originalUrl, source, sourceItemId)
      : `local-${Date.now()}`;
    const fallbackTitle = cleanedTitle.length > 0 ? cleanedTitle : '未命名收藏';
    const category = this.classify(fallbackTitle);
    return {
      source: source,
      sourceItemId: sourceItemId,
      originalUrl: originalUrl,
      canonicalUrl: canonicalUrl,
      title: fallbackTitle,
      author: this.extractAuthor(titlePart),
      category: category,
      tags: this.buildTags(fallbackTitle, category, source),
      summary: fallbackTitle.length > 92 ? `${fallbackTitle.substring(0, 92)}…` : fallbackTitle
    };
  }

  private trimUrl(value: string): string {
    let result = value.trim();
    while (result.length > 0 && '.,!?;:，。！？；：）)】]'.includes(result.charAt(result.length - 1))) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }

  private cleanTitle(value: string): string {
    let result = value.trim();
    result = result.replace(/^\d+(?:\.\d+)?\s*/, '');
    result = result.replace(/[【\[]([^】\]]+?)[-—–]\s*哔哩哔哩[】\]]/gi, '$1');
    result = result.replace(/【抖音精选】/g, '');
    result = result.replace(/哔哩哔哩/gi, '');
    result = result.replace(/点击链接\s*or\s*复制打开app/gi, '');
    result = result.replace(/复制此链接[，,]?\s*打开抖音[^。！!\n]*/g, '');
    result = result.replace(/看看/g, '');
    result = result.replace(/【[^】]+的作品】/g, '');
    result = result.replace(/^[，,。！!：:\s]+/g, '');
    result = result.replace(/[，,。！!：:\s]+$/g, '');
    result = result.replace(/\s+/g, ' ').trim();
    return result;
  }

  private extractAuthor(value: string): string {
    const authorMatch: RegExpMatchArray | null = value.match(/【([^】]+)的作品】/);
    return authorMatch === null ? '' : authorMatch[1];
  }

  private detectSource(url: string): string {
    if (this.matchesDomain(url, ['douyin.com', 'iesdouyin.com'])) {
      return '抖音精选';
    }
    if (this.matchesDomain(url, ['bilibili.com', 'b23.tv'])) {
      return '哔哩哔哩';
    }
    if (this.matchesDomain(url, ['xiaohongshu.com', 'xhslink.com'])) {
      return '小红书';
    }
    if (this.matchesDomain(url, ['kuaishou.com', 'gifshow.com'])) {
      return '快手';
    }
    if (this.matchesDomain(url, ['weibo.com', 'weibo.cn'])) {
      return '微博';
    }
    if (this.matchesDomain(url, ['youtube.com', 'youtu.be'])) {
      return 'YouTube';
    }
    return '';
  }

  private matchesDomain(url: string, domains: string[]): boolean {
    const hostMatch: RegExpMatchArray | null = url.match(/^https?:\/\/([^\/?#]+)/i);
    if (hostMatch === null) {
      return false;
    }
    const host = hostMatch[1].toLowerCase();
    for (let index = 0; index < domains.length; index++) {
      const domain = domains[index].toLowerCase();
      if (host === domain || host.endsWith(`.${domain}`)) {
        return true;
      }
    }
    return false;
  }

  private extractSourceItemId(url: string, source: string): string {
    let patterns: RegExp[] = [];
    if (source === '哔哩哔哩') {
      patterns = [
        /\/video\/(BV[A-Za-z0-9]+)/i,
        /\/video\/(av\d+)/i,
        /[?&]bvid=(BV[A-Za-z0-9]+)/i
      ];
    } else if (source === '抖音精选') {
      patterns = [
        /\/video\/(\d+)/,
        /\/note\/(\d+)/,
        /\/slides\/(\d+)/,
        /[?&](?:modal_id|aweme_id)=(\d+)/
      ];
    } else {
      patterns = [
        /\/video\/([A-Za-z0-9_-]+)/i,
        /\/note\/([A-Za-z0-9_-]+)/i
      ];
    }
    for (let index = 0; index < patterns.length; index++) {
      const match: RegExpMatchArray | null = url.match(patterns[index]);
      if (match !== null) {
        return match[1];
      }
    }
    return '';
  }

  private toCanonicalUrl(url: string, source: string, sourceItemId: string): string {
    if (source === '抖音精选' && sourceItemId.length > 0) {
      return `https://www.douyin.com/video/${sourceItemId}`;
    }
    if (source === '哔哩哔哩' && sourceItemId.length > 0) {
      return `https://www.bilibili.com/video/${sourceItemId}`;
    }
    return url.split('#')[0];
  }

  private classify(text: string): string {
    if (this.containsAny(text, ['壶铃', '健身', '运动', '减脂', '增肌', '瑜伽', '跑步', '训练', '拉伸'])) {
      return '健康运动';
    }
    if (this.containsAny(text, ['教程', '学习', '英语', '考研', '职场', 'Excel', '论文', '科研', '课程', '知识'])) {
      return '学习成长';
    }
    if (this.containsAny(text, ['手机', '电脑', 'AI', '编程', '代码', '科技', '数码', '相机', '摄影', '软件'])) {
      return '科技数码';
    }
    if (this.containsAny(text, ['电影', '电视剧', '综艺', '脱口秀', '经典', '解说', '纪录片', '剧情'])) {
      return '影视娱乐';
    }
    if (this.containsAny(text, ['收纳', '家居', '穿搭', '护肤', '装修', '生活'])) {
      return '生活方式';
    }
    if (this.containsAny(text, ['食谱', '做菜', '美食', '烘焙', '咖啡', '餐厅'])) {
      return '美食';
    }
    if (this.containsAny(text, ['旅行', '旅游', '攻略', '酒店', '景点', '城市'])) {
      return '旅行';
    }
    return '待整理';
  }

  private replacePlatformTag(tags: string, source: string): string {
    const platformTags = ['抖音精选', '哔哩哔哩', '小红书', '快手', '微博', 'YouTube', '其他来源'];
    const parts = tags.split('|').filter((value: string) =>
      value.length > 0 && !platformTags.includes(value)
    );
    parts.push(source);
    return parts.join('|');
  }

  private buildTags(title: string, category: string, source: string): string {
    const candidates: string[] = [];
    const tagPatterns: string[] = [
      '教程', '健身', '减脂', '增肌', 'AI', '编程', '摄影', '电影', '脱口秀',
      '收纳', '美食', '旅行', '职场', '学习', '科研'
    ];
    for (let index = 0; index < tagPatterns.length && candidates.length < 3; index++) {
      if (title.toLowerCase().includes(tagPatterns[index].toLowerCase())) {
        candidates.push(tagPatterns[index]);
      }
    }
    if (candidates.length === 0 && category !== '待整理') {
      candidates.push(category);
    }
    candidates.push(source);
    return candidates.join('|');
  }

  private containsAny(text: string, words: string[]): boolean {
    const normalized = text.toLowerCase();
    for (let index = 0; index < words.length; index++) {
      if (normalized.includes(words[index].toLowerCase())) {
        return true;
      }
    }
    return false;
  }
}
