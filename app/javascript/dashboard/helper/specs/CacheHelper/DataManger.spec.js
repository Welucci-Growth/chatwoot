import { DataManager } from '../../CacheHelper/DataManager';

describe('DataManager', () => {
  const accountId = 'test-account';
  let dataManager;

  beforeEach(async () => {
    dataManager = new DataManager(accountId);
    await dataManager.initDb();
  });

  afterEach(async () => {
    const tx = dataManager.db.transaction(
      dataManager.modelsToSync,
      'readwrite'
    );
    dataManager.modelsToSync.forEach(modelName => {
      tx.objectStore(modelName).clear();
    });
    await tx.done;
  });

  describe('initDb', () => {
    it('should initialize the database', async () => {
      expect(dataManager.db).not.toBeNull();
    });

    it('keeps a separate database per signed-in user', async () => {
      document.cookie = `cw_d_session_info=${encodeURIComponent(
        JSON.stringify({ uid: 'agent@example.com' })
      )}`;
      const agentManager = new DataManager(accountId);
      await agentManager.initDb();

      expect(agentManager.db.name).toBe(
        `cw-store-${accountId}-agent@example.com`
      );
      expect(dataManager.db.name).toBe(`cw-store-${accountId}-`);
      document.cookie =
        'cw_d_session_info=; expires=Thu, 01 Jan 1970 00:00:00 GMT';
    });

    it('should return the same instance of the database', async () => {
      const db1 = await dataManager.initDb();
      const db2 = await dataManager.initDb();
      expect(db1).toBe(db2);
    });
  });

  describe('validateModel', () => {
    it('should throw an error for empty input', async () => {
      expect(() => {
        dataManager.validateModel();
      }).toThrow();
    });

    it('should throw an error for invalid model', async () => {
      expect(() => {
        dataManager.validateModel('invalid-model');
      }).toThrow();
    });

    it('should not throw an error for valid model', async () => {
      expect(dataManager.validateModel('label')).toBeTruthy();
    });
  });

  describe('replace', () => {
    it('should replace existing data in the specified model', async () => {
      const inboxData = [
        { id: 1, name: 'inbox-1' },
        { id: 2, name: 'inbox-2' },
      ];
      const newData = [
        { id: 3, name: 'inbox-3' },
        { id: 4, name: 'inbox-4' },
      ];

      await dataManager.push({ modelName: 'inbox', data: inboxData });
      await dataManager.replace({ modelName: 'inbox', data: newData });
      const result = await dataManager.get({ modelName: 'inbox' });
      expect(result).toEqual(newData);
    });
  });

  describe('push', () => {
    it('should add data to the specified model', async () => {
      const inboxData = { id: 1, name: 'inbox-1' };

      await dataManager.push({ modelName: 'inbox', data: inboxData });
      const result = await dataManager.get({ modelName: 'inbox' });
      expect(result).toEqual([inboxData]);
    });

    it('should add multiple items to the specified model if an array of data is provided', async () => {
      const inboxData = [
        { id: 1, name: 'inbox-1' },
        { id: 2, name: 'inbox-2' },
      ];

      await dataManager.push({ modelName: 'inbox', data: inboxData });
      const result = await dataManager.get({ modelName: 'inbox' });
      expect(result).toEqual(inboxData);
    });
  });

  describe('get', () => {
    it('should return all data in the specified model', async () => {
      const inboxData = [
        { id: 1, name: 'inbox-1' },
        { id: 2, name: 'inbox-2' },
      ];

      await dataManager.push({ modelName: 'inbox', data: inboxData });
      const result = await dataManager.get({ modelName: 'inbox' });
      expect(result).toEqual(inboxData);
    });
  });

  describe('setCacheKeys', () => {
    it('should add cache keys for each model', async () => {
      const cacheKeys = { inbox: 'cache-key-1', label: 'cache-key-2' };

      await dataManager.setCacheKeys(cacheKeys);
      const result = await dataManager.getCacheKey('inbox');
      expect(result).toEqual(cacheKeys.inbox);
    });
  });
});
