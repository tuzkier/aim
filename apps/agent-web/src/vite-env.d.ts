declare module "*.css";

/**
 * 开发回退用的账号来自 `.env.local`（不进版本库）。
 * 显式声明而不是引 `vite/client`：那个全局类型会把一堆无关的模块声明也拉进来。
 */
interface ImportMetaEnv {
  readonly DEV: boolean;
  readonly PROD: boolean;
  readonly VITE_AIM_DEV_PHONE?: string;
  readonly VITE_AIM_DEV_PASSWORD?: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}
