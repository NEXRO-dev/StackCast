"use client";

import { useEffect, useState } from "react";

export function Avatar({
  name,
  imageURL,
  className = "",
}: {
  name: string;
  imageURL?: string | null;
  className?: string;
}) {
  const [failedURL, setFailedURL] = useState<string | null>(null);
  const initial = name.trim().slice(0, 1).toUpperCase() || "?";
  const visibleImageURL = imageURL && imageURL !== failedURL ? imageURL : null;

  useEffect(() => {
    if (imageURL !== failedURL) return;
    const retry = window.setTimeout(() => setFailedURL(null), 30_000);
    return () => window.clearTimeout(retry);
  }, [failedURL, imageURL]);

  return (
    <span className={`avatar ${visibleImageURL ? "avatar-photo" : ""} ${className}`.trim()}>
      {visibleImageURL ? (
        // A native image is intentional here: the URL is user data and the
        // error event is used to fall back when a provider image expires.
        // eslint-disable-next-line @next/next/no-img-element
        <img
          className="avatar-image"
          src={visibleImageURL}
          alt={`${name}のプロフィール画像`}
          referrerPolicy="no-referrer"
          onError={() => setFailedURL(visibleImageURL)}
        />
      ) : (
        <span aria-hidden="true">{initial}</span>
      )}
    </span>
  );
}
