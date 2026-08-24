const mongoose = require("mongoose");

// All uploaded attachments (photos, sketch, signatures) live in one GridFS
// bucket. The bucket wraps mongoose.connection.db, so it can only be built
// once Mongo is connected — build it lazily per call rather than at module
// load time (index.js connects asynchronously after this module is required).
const BUCKET_NAME = "attachments";

function getBucket() {
  return new mongoose.mongo.GridFSBucket(mongoose.connection.db, { bucketName: BUCKET_NAME });
}

function storeBuffer(buffer, filename, metadata = {}) {
  return new Promise((resolve, reject) => {
    const uploadStream = getBucket().openUploadStream(filename, { metadata });
    uploadStream.once("error", reject);
    uploadStream.once("finish", () => resolve(uploadStream.id));
    uploadStream.end(buffer);
  });
}

function openDownloadStream(fileId) {
  return getBucket().openDownloadStream(new mongoose.Types.ObjectId(fileId));
}

// Drains a GridFS file into a single Buffer — for callers that need the
// whole file in memory (pdf.service.js embedding images), as opposed to
// files.js's streamed response.
function getFileBuffer(fileId) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    const downloadStream = openDownloadStream(fileId);
    downloadStream.on("data", (chunk) => chunks.push(chunk));
    downloadStream.once("error", reject);
    downloadStream.once("end", () => resolve(Buffer.concat(chunks)));
  });
}

async function getFileMetadata(fileId) {
  const files = await getBucket()
    .find({ _id: new mongoose.Types.ObjectId(fileId) })
    .toArray();
  return files[0] || null;
}

async function deleteFile(fileId) {
  await getBucket().delete(new mongoose.Types.ObjectId(fileId));
}

module.exports = { storeBuffer, openDownloadStream, getFileBuffer, getFileMetadata, deleteFile, BUCKET_NAME };
