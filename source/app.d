module something;

// Phobos Runtime Library
debug import std.stdio : writeln, writefln;
import core.sys.windows.windows;
import std.exception : enforce;
import std.conv : to;
import std.utf: toUTF16z;
import std.path: dirName;
import std.string : toStringz;
// Derelict Library
import derelict.util.exception;
import derelict.sdl2.sdl;
import derelict.sdl2.image;
// User Library
//

extern (Windows)
{
    // SetSearchPathMode関数のフラグ
    const DWORD BASE_SEARCH_PATH_ENABLE_SAFE_SEARCHMODE = 0x00000001;
    const DWORD BASE_SEARCH_PATH_PERMANENT              = 0x00008000;

    // SearchPathが使用するプロセス検索モードを指定
    BOOL SetSearchPathMode(DWORD Flags);
}

static this()
{
    // 実行ファイルのフルパスとファイル名を取得するためのバッファ
    wchar[MAX_PATH] buffer;
    // 実行ファイルのフルパスとファイル名を取得
    GetModuleFileName(null, buffer.ptr, buffer.length);
    // SearchPathに安全なプロセス検索モードを使用する
    SetSearchPathMode(BASE_SEARCH_PATH_ENABLE_SAFE_SEARCHMODE | BASE_SEARCH_PATH_PERMANENT);
    // DLLの検索パスからCWDを削除
    SetDllDirectory("");
    // DLLの検索パスにlibディレクトリのフルパスを指定
    SetDllDirectory((buffer.dirName ~ "\\library").toUTF16z);

    // Derelict 共有ライブラリの読み込み
    try
    {
        DerelictSDL2.load(buffer.dirName.to!string ~ "\\library\\sdl2.dll");
        DerelictSDL2Image.load(buffer.dirName.to!string ~ "\\library\\sdl2_image.dll");
    }
    catch (SymbolLoadException sle)
    {
        throw new Exception (sle.msg);
    }
    catch (SharedLibLoadException slle)
    {
        throw new Exception (slle.msg);
    }
}

// エラー発生時はSDL_GetError()を参照して例外をthrowする
T enforceSdl(T)(T value, string file = __FILE__, size_t line = __LINE__)
{
    return enforce(value, SDL_GetError().to!string, file, line);
}

// 画像ファイルを読み込み、非矩形ウィンドウに適用する
void shapedWindowFromImage(    SDL_Window*   window,
                               SDL_Renderer* renderer,
                           ref SDL_Surface*  surface,
                           ref SDL_Texture*  texture,
                               string        path)
{
    // 背景画像の読み込み
    auto oldSurface = surface;
    //surface = enforceSdl(IMG_Load(path.toStringz));
    surface = enforceSdl(IMG_LoadTyped_RW(SDL_RWFromFile(path.toStringz, "rb"), 1, "PNG"));
    scope(success) SDL_FreeSurface(oldSurface);
    scope(failure) { SDL_FreeSurface(surface); surface = oldSurface; }

    // テクスチャの生成
    auto oldTexture = texture;
    texture = enforceSdl(SDL_CreateTextureFromSurface(renderer, surface));
    scope(success) SDL_DestroyTexture(oldTexture);
    scope(failure) { SDL_DestroyTexture(texture); texture = oldTexture; }

    SDL_Rect rect;
    enforceSdl(SDL_QueryTexture(texture, null, null, &rect.w, &rect.h) == 0);
    SDL_SetWindowSize(window, rect.w, rect.h);
    SDL_GetWindowPosition(window, &rect.x, &rect.y);
    scope(exit) SDL_SetWindowPosition(window, rect.x, rect.y);

    // 画像の透過色を取得
    SDL_WindowShapeMode shapeMode;
    if (surface.format.Amask != 0)
    {
        // アルファ値がある場合それを使用
        shapeMode.mode = ShapeModeDefault;
        //shapeMode.parameters.binarizationCutoff = 1;
    }
    else
    {
        // 画像の左上座標(0, 0)の色を透過色と見なす
        shapeMode.mode = ShapeModeColorKey;

        SDL_LockSurface(surface);
        Uint32 pixel = ( cast(Uint32*)(surface.pixels) )[0];
        // R,G,Bの各色成分を得る
        SDL_Color tColor;
        SDL_GetRGB(pixel, surface.format, &tColor.r, &tColor.g, &tColor.b);
        SDL_UnlockSurface(surface);

        shapeMode.parameters.colorKey = tColor;
    }

    // 非矩形ウィンドウに設定
    enforceSdl(SDL_SetWindowShape(window, surface, &shapeMode) == 0);
}

// 画面描画
public void render(SDL_Renderer* renderer, SDL_Texture* texture)
{
    enforceSdl(SDL_RenderClear(renderer) == 0);
    enforceSdl(SDL_RenderCopy(renderer, texture, null, null) == 0);
    SDL_RenderPresent(renderer);
}

// SDL_SetWindowHitTestに渡されるコールバック関数
extern (C) SDL_HitTestResult
hitTestCallback(SDL_Window* window, const(SDL_Point)* area, void* data) nothrow @nogc
{
    // クリックされた座標(area.x, area.y)とSDL_GetWindowSizeなどを利用して
    // ドラッグ可能な領域を限定したり、サイズ変更可能な領域を指定したりなども可能
    return SDL_HITTEST_DRAGGABLE;
}



/// Entry-point
void main(string[] args)
{
    debug foreach (arg; args) arg.writeln;

    // SDLライブラリの初期化
    enforceSdl(SDL_Init(SDL_INIT_EVERYTHING) == 0);
    scope(exit) SDL_Quit();

    // ウインドウの生成
    auto window = enforceSdl(
        SDL_CreateShapedWindow("Something",
                               SDL_WINDOWPOS_UNDEFINED,
                               SDL_WINDOWPOS_UNDEFINED,
                               800,
                               600,
                               SDL_WINDOW_BORDERLESS));
    scope(exit) SDL_DestroyWindow(window);
    SDL_SetWindowPosition(window, SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED);

    // レンダラーの生成
    auto renderer = enforceSdl(SDL_CreateRenderer(window, -1, 0));
    scope(exit) SDL_DestroyRenderer(renderer);

    SDL_Surface* surface;
    SDL_Texture* texture;
    // 画像ファイルを読み込み、非矩形ウィンドウに適用
    shapedWindowFromImage(window, renderer, surface, texture, "./image/background.png");
    scope(exit) SDL_FreeSurface(surface);
    scope(exit) SDL_DestroyTexture(texture);

    // 描画実行
    render(renderer, texture);

    // タイトルバーやウィンドウ枠の代わりになる(ドラッグで移動やサイズ変更可能な)領域を設定
    enforceSdl(SDL_SetWindowHitTest(window, &hitTestCallback, cast(void*)null) == 0);

    // イベントに対応するアクションの定義
    bool delegate(SDL_Event)[typeof(SDL_Event.type)] action;

    // SDLライブラリの終了
    action[SDL_QUIT] = (SDL_Event event) { return false; };
    // 閉じるボタンの代わりにEscキーで終了
    action[SDL_KEYDOWN] = (SDL_Event event) { return event.key.keysym.sym != SDLK_ESCAPE; };
    // 再描画実行
    action[SDL_WINDOWEVENT] = (SDL_Event event) {
        if (event.window.event == SDL_WINDOWEVENT_EXPOSED)
            render(renderer, texture);
        return true;
    };
    // ドロップファイルの処理
    action[SDL_DROPFILE] = (SDL_Event event) {
        char* droppedPath = event.drop.file;
        scope(exit) SDL_free(droppedPath);
        debug "droppedPath: %s".writefln(droppedPath.to!string);
        shapedWindowFromImage(window, renderer, surface, texture, droppedPath.to!string);
        return true;
    };
    // マウスホイールの処理
    action[SDL_MOUSEWHEEL] = (SDL_Event event) {
        const direction = (event.wheel.direction == SDL_MOUSEWHEEL_NORMAL ? 1 : -1);
        float opacity; // 不透明度 (0.0f～1.0f)
        enforceSdl(SDL_GetWindowOpacity(window, &opacity) == 0);
        // ホイールを奥に回した
        if (event.wheel.y == direction) {
            debug "wheel: up".writeln;
            opacity = opacity > 0.9f ? 1.0f : opacity + 0.1f;
        }
        // ホイールを手前に回した
        else if (event.wheel.y == -direction) {
            debug "wheel: down".writeln;
            opacity = opacity < 0.2f ? 0.1f : opacity - 0.1f;
        }
        enforceSdl(SDL_SetWindowOpacity(window, opacity) == 0);
        return true;
    };

    // イベントループ
    for (SDL_Event event; SDL_WaitEvent(&event);)
    {
        if (event.type in action)
        {
            // アクション実行
            if ( !action[event.type](event) )
                break;
        }
    }
}
