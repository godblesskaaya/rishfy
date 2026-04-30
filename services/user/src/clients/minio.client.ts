import { S3Client, PutObjectCommand } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { config } from '../config.js';

// Re-export so callers don't need the AWS SDK directly
export { PutObjectCommand };

let _client: S3Client | null = null;

export function getS3Client(): S3Client {
  if (!_client) {
    _client = new S3Client({
      endpoint: config.MINIO_ENDPOINT,
      region: 'us-east-1',
      credentials: {
        accessKeyId: config.MINIO_ACCESS_KEY,
        secretAccessKey: config.MINIO_SECRET_KEY,
      },
      forcePathStyle: true,
    });
  }
  return _client;
}

export async function generateUploadUrl(
  bucket: string,
  key: string,
  contentType: string,
  expiresIn = 300,
): Promise<string> {
  const command = new PutObjectCommand({ Bucket: bucket, Key: key, ContentType: contentType });
  return getSignedUrl(getS3Client(), command, { expiresIn });
}

export function buildObjectUrl(bucket: string, key: string): string {
  return `${config.MINIO_ENDPOINT}/${bucket}/${key}`;
}
