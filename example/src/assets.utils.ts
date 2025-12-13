import { useEffect, useState } from 'react';
import { Dirs, FileSystem } from 'react-native-file-access';
import { Image } from 'react-native';

export function useAsset(asset: number | string) {
  const [path, setPath] = useState<string | undefined>(undefined);
  useEffect(() => {
    const loadAsset = async () => {
      let localPath: string;

      if (typeof asset === 'number') {
        // Bundled asset via require()
        const source = Image.resolveAssetSource(asset);
        const filename = source.uri.split('/').pop() || 'document.pdf';
        localPath = `${Dirs.CacheDir}/${filename}`;

        // Download from Metro/bundle URL to local cache
        await FileSystem.fetch(source.uri, { path: localPath });
      } else {
        // Native asset by name
        localPath = `${Dirs.CacheDir}/${asset}`;
        await FileSystem.cpAsset(asset, localPath).catch(() => {});
      }

      setPath(localPath);
    };

    loadAsset().catch(console.warn);
  }, [asset]);

  return path;
}
