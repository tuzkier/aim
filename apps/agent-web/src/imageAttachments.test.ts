import { expect, test } from "vitest";
import { dataUrlToFile, fitWithin, imagesContext, numberImages } from "./imageAttachments";

test("large photos shrink to fit 1600 on the long edge, small ones stay", () => {
  expect(fitWithin(4032, 3024, 1600)).toEqual({ width: 1600, height: 1200 });
  expect(fitWithin(3024, 4032, 1600)).toEqual({ width: 1200, height: 1600 });
  expect(fitWithin(800, 600, 1600)).toEqual({ width: 800, height: 600 });
});

test("the model sees every photo of the conversation in order", () => {
  expect(imagesContext([])).toBeNull();
  expect(
    imagesContext([
      { id: "a", message: 1, index: 1 },
      { id: "b", message: 3, index: 1 },
      { id: "c", message: 3, index: 2 },
    ]),
  ).toBe(
    "Photos the user sent in this conversation (use these ids in attachmentIds):\n" +
      "- message 1, photo 1: a\n- message 3, photo 1: b\n- message 3, photo 2: c",
  );
});

test("photos are numbered in the order they were picked, not the order uploads finished", () => {
  expect(
    numberImages([
      { id: "second", message: 2, order: 5 },
      { id: "first", message: 2, order: 4 },
      { id: "earlier", message: 1, order: 1 },
    ]),
  ).toEqual([
    { id: "earlier", message: 1, index: 1 },
    { id: "first", message: 2, index: 1 },
    { id: "second", message: 2, index: 2 },
  ]);
});

test("a photo handed over by the app becomes a file the composer can take", () => {
  const file = dataUrlToFile("data:image/jpeg;base64,/9j/", "photo.jpg");
  expect(file.type).toBe("image/jpeg");
  expect(file.name).toBe("photo.jpg");
  expect(file.size).toBe(3);
});
