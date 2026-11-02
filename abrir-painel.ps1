# ============================================================
#  Painel de Demandas
#  Janela propria (sem barra de titulo) com a pagina dentro via WebView2.
#  Fica fixa na esquerda do ultrawide e reserva essa faixa da tela.
#  Win+Espaco esconde/mostra.
# ============================================================

# ---- AJUSTES -----------------------------------------------
# Largura do painel em pixels reais da tela.
$Largura = 440
# Qual monitor usar:
#   'auto'  = o maior monitor que NAO e o principal (seu ultrawide)
#   0, 1, 2 = numero do monitor (0 = primeiro encontrado)
$Monitor = 'auto'
# ------------------------------------------------------------

$ErrorActionPreference = 'Stop'
$pasta  = Split-Path -Parent $MyInvocation.MyCommand.Path
$html   = Join-Path $pasta 'index.html'
$lib    = Join-Path $pasta 'lib'
$dados  = Join-Path $env:LOCALAPPDATA 'PainelDemandas'
$perfil = Join-Path $dados 'webview'
New-Item -ItemType Directory -Force -Path $dados | Out-Null
$log = Join-Path $dados 'diagnostico.txt'
function Anotar($t) { try { Add-Content -Path $log -Value ((Get-Date -Format 'HH:mm:ss ') + $t) } catch {} }
trap { Anotar ("ERRO: " + $_); break }
Anotar "iniciando (PowerShell $($PSVersionTable.PSVersion))"

# Encerra versoes anteriores deste painel (e o Edge que as versoes antigas usavam)
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -like '*abrir-painel.ps1*' } |
    ForEach-Object { Anotar "encerrando versao anterior (PID $($_.ProcessId))"; Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
$velhos = @(Get-CimInstance Win32_Process -Filter "Name='msedge.exe'" | Where-Object { $_.CommandLine -like '*PainelDemandas\perfil-edge*' })
if ($velhos.Count -gt 0) {
    Anotar "fechando Edge da versao antiga ($($velhos.Count) processos)"
    $velhos | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Milliseconds 800
}

# Traz as demandas salvas na versao antiga (Edge) para o WebView2, so na primeira vez
$lsVelho = Join-Path $dados 'perfil-edge\Default\Local Storage'
$lsNovo  = Join-Path $perfil 'EBWebView\Default\Local Storage'
if ((Test-Path $lsVelho) -and -not (Test-Path $lsNovo)) {
    New-Item -ItemType Directory -Force -Path (Split-Path $lsNovo) | Out-Null
    Copy-Item -Recurse -Force $lsVelho $lsNovo
    Anotar "demandas copiadas da versao antiga"
}

# Atualizacao trouxe bibliotecas novas: so da para trocar com o painel antigo fechado (feito acima)
$libNovo = Join-Path $pasta 'lib-novo'
if (Test-Path $libNovo) {
    Copy-Item (Join-Path $libNovo '*') $lib -Force
    Remove-Item $libNovo -Recurse -Force
    Anotar "bibliotecas atualizadas"
}

$mutex = New-Object System.Threading.Mutex($false, 'Local\PainelDemandasHost')
# uma versao encerrada a forca deixa o mutex "abandonado": isso conta como liberado
try { $livre = $mutex.WaitOne(5000) } catch [System.Threading.AbandonedMutexException] { $livre = $true }
if (-not $livre) { Anotar "outro painel ainda esta aberto"; exit }

Add-Type -Path (Join-Path $lib 'Microsoft.Web.WebView2.Core.dll')
Add-Type -Path (Join-Path $lib 'Microsoft.Web.WebView2.WinForms.dll')
Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing, System.Management,
    (Join-Path $lib 'Microsoft.Web.WebView2.Core.dll'), (Join-Path $lib 'Microsoft.Web.WebView2.WinForms.dll') -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Forms;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;

public class Painel : Form
{
    // ---------- Win32 ----------
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] public struct APPBARDATA {
        public int cbSize; public IntPtr hWnd; public uint uCallbackMessage; public uint uEdge; public RECT rc; public IntPtr lParam; }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] public struct MONITORINFO {
        public int cbSize; public RECT rcMonitor; public RECT rcWork; public uint dwFlags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string szDevice; }
    [DllImport("shell32.dll")] static extern UIntPtr SHAppBarMessage(uint msg, ref APPBARDATA d);
    [DllImport("user32.dll")] static extern uint RegisterWindowMessage(string s);
    [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint f);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder sb, int max);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] static extern IntPtr GetAncestor(IntPtr h, uint flags);
    delegate bool EnumMonProc(IntPtr m, IntPtr dc, ref RECT r, IntPtr d);
    [DllImport("user32.dll")] static extern bool EnumDisplayMonitors(IntPtr dc, IntPtr clip, EnumMonProc cb, IntPtr d);
    [DllImport("user32.dll", CharSet = CharSet.Unicode, EntryPoint = "GetMonitorInfoW")] static extern bool GetMonitorInfo(IntPtr m, ref MONITORINFO mi);
    [DllImport("user32.dll")] static extern bool SetProcessDpiAwarenessContext(IntPtr v);
    [DllImport("user32.dll")] static extern IntPtr SetThreadDpiAwarenessContext(IntPtr v);
    delegate IntPtr HookProc(int code, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")] static extern IntPtr SetWindowsHookEx(int id, HookProc proc, IntPtr mod, uint thread);
    [DllImport("user32.dll")] static extern bool UnhookWindowsHookEx(IntPtr h);
    [DllImport("user32.dll")] static extern IntPtr CallNextHookEx(IntPtr h, int code, IntPtr wParam, IntPtr lParam);
    [DllImport("kernel32.dll")] static extern IntPtr GetModuleHandle(string name);
    [DllImport("user32.dll")] static extern short GetAsyncKeyState(int vk);
    [DllImport("user32.dll")] static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
    [DllImport("gdi32.dll")] static extern IntPtr CreateRectRgn(int l, int t, int r, int b);
    [DllImport("user32.dll")] static extern int SetWindowRgn(IntPtr h, IntPtr rgn, bool redraw);
    [DllImport("dwmapi.dll")] static extern int DwmSetWindowAttribute(IntPtr h, int attr, ref int v, int size);

    const uint ABM_NEW = 0, ABM_REMOVE = 1, ABM_QUERYPOS = 2, ABM_SETPOS = 3, ABE_LEFT = 0, ABE_RIGHT = 2, ABN_POSCHANGED = 1;
    static readonly IntPtr TOPMOST = new IntPtr(-1), NOTOPMOST = new IntPtr(-2), BOTTOM = new IntPtr(1);
    const uint NOSIZE = 0x0001, NOMOVE = 0x0002, NOZORDER = 0x0004, NOACTIVATE = 0x0010;

    // ---------- estado ----------
    public static string logPath, configPath, dadosPath, appPath;
    int largura; string monitorPref; string html; string perfil;
    string monitorEscolhido = ""; bool direita; // escolhas feitas na engrenagem (salvas em configPath)
    uint cbMsg; APPBARDATA abd; bool registrado;
    IntPtr monitor; RECT faixa;           // area reservada (posicao final do painel)
    WebView2 web; bool pronto;
    bool escondido, animando, cedido;
    Timer relogio, anim; DateTime animInicio; bool animMostrando;
    HookProc ganchoProc; IntPtr gancho;
    const double ANIM_MS = 360;
    static readonly Color FUNDO_CLARO = Color.FromArgb(243, 245, 248), FUNDO_ESCURO = Color.FromArgb(14, 17, 22);

    public static void Rodar(int largura, string monitorPref, string html, string perfil)
    {
        try { SetProcessDpiAwarenessContext(new IntPtr(-4)); } catch { }
        try { SetThreadDpiAwarenessContext(new IntPtr(-4)); } catch { } // pixels reais mesmo se o PowerShell ja definiu outro modo
        Application.EnableVisualStyles();
        Painel p = new Painel(largura, monitorPref, html, perfil);
        Application.Run(p);
    }

    Painel(int largura, string monitorPref, string html, string perfil)
    {
        this.largura = largura; this.monitorPref = monitorPref; this.html = html; this.perfil = perfil;
        LerConfig();
        FormBorderStyle = FormBorderStyle.None;   // sem barra de titulo, botoes ou bordas
        ShowInTaskbar = false;
        StartPosition = FormStartPosition.Manual;
        TopMost = true;
        BackColor = FUNDO_CLARO;                   // nunca preto enquanto a pagina carrega
        Text = "Painel de Demandas";

        web = new WebView2();
        web.Dock = DockStyle.Fill;
        web.DefaultBackgroundColor = FUNDO_CLARO;
        web.CreationProperties = Opcoes();
        Controls.Add(web);
    }

    CoreWebView2CreationProperties Opcoes()
    {
        return new CoreWebView2CreationProperties {
            UserDataFolder = perfil,
            AdditionalBrowserArguments = "--disable-background-networking --disable-component-update --disable-sync " +
                "--renderer-process-limit=1 --disable-features=msSmartScreenProtection,msEdgeSidebarV2"
        };
    }

    // janela de ferramenta: fora da barra de tarefas e do Alt+Tab
    protected override CreateParams CreateParams {
        get { CreateParams cp = base.CreateParams; cp.ExStyle |= 0x80; return cp; }
    }

    protected override async void OnLoad(EventArgs e)
    {
        base.OnLoad(e);
        // cantos retos no Windows 11 (painel encostado na borda)
        int semCanto = 1; DwmSetWindowAttribute(Handle, 33, ref semCanto, 4);

        cbMsg = RegisterWindowMessage("PainelDemandasAppBar");
        abd = new APPBARDATA();
        abd.cbSize = Marshal.SizeOf(typeof(APPBARDATA));
        abd.hWnd = Handle;
        abd.uCallbackMessage = cbMsg;
        Registrar();
        Reservar();

        ganchoProc = Gancho;
        gancho = SetWindowsHookEx(13, ganchoProc, GetModuleHandle(null), 0);
        if (gancho == IntPtr.Zero) Log("nao foi possivel capturar Win+Espaco");

        relogio = new Timer(); relogio.Interval = 1000;
        relogio.Tick += delegate { Verificar(); };
        relogio.Start();

        try {
            CoreWebView2Environment.SetLoaderDllFolderPath(System.IO.Path.GetDirectoryName(typeof(CoreWebView2).Assembly.Location));
            await web.EnsureCoreWebView2Async(null);
            CoreWebView2Settings s = web.CoreWebView2.Settings;
            s.AreDefaultContextMenusEnabled = false;
            s.AreDevToolsEnabled = false;
            s.IsStatusBarEnabled = false;
            s.IsZoomControlEnabled = false;
            s.AreBrowserAcceleratorKeysEnabled = false;   // sem Ctrl+R, F5, Ctrl+P etc.
            s.IsPasswordAutosaveEnabled = false; s.IsGeneralAutofillEnabled = false;
            web.CoreWebView2.WebMessageReceived += MensagemDaPagina;
            web.CoreWebView2.Navigate(new Uri(html).AbsoluteUri);
            pronto = true;
            Log("painel aberto");
        } catch (Exception ex) {
            Log("ERRO ao iniciar o WebView2: " + ex.Message);
        }
        MedirUso();
    }

    // a pagina avisa qual tema esta usando, para o fundo da janela combinar
    void MensagemDaPagina(object sender, CoreWebView2WebMessageReceivedEventArgs e)
    {
        string m = "";
        try { m = e.TryGetWebMessageAsString(); } catch { }
        if (m == "config?") { EnviarTelas(); return; }
        if (m.StartsWith("backup:demandas:")) { Backup("demandas", m.Substring(16)); return; }
        if (m == "restaurar?") { // a pagina compara e fica com a versao mais nova
            string b = LerBackup("demandas");
            try { web.CoreWebView2.PostWebMessageAsString("{\"restaurar\":" + (b ?? "null") + "}"); } catch { }
            return;
        }
        if (m.StartsWith("config:")) { AplicarConfig(m.Substring(7)); return; }
        if (m == "tema:escuro" || m == "tema:claro") {
            Color c = m == "tema:escuro" ? FUNDO_ESCURO : FUNDO_CLARO;
            BackColor = c; web.DefaultBackgroundColor = c;
        }
    }

    // ---------- configuracao da engrenagem: "monitor|lado|largura" ----------
    void LerConfig()
    {
        try {
            if (configPath == null || !System.IO.File.Exists(configPath)) return;
            string[] p = System.IO.File.ReadAllText(configPath).Trim().Split('|');
            if (p.Length > 0) monitorEscolhido = p[0];
            if (p.Length > 1) direita = p[1] == "direita";
            int l; if (p.Length > 2 && int.TryParse(p[2], out l)) largura = Math.Max(300, Math.Min(800, l));
        } catch (Exception e) { Log("config ilegivel: " + e.Message); }
    }

    void SalvarConfig()
    {
        try { System.IO.File.WriteAllText(configPath, monitorEscolhido + "|" + (direita ? "direita" : "esquerda") + "|" + largura); }
        catch (Exception e) { Log("nao foi possivel salvar a config: " + e.Message); }
    }

    static string J(string t) { return "\"" + t.Replace("\\", "\\\\").Replace("\"", "\\\"") + "\""; }

    // manda para a pagina os monitores e a escolha atual (ela desenha o mapa da engrenagem)
    void EnviarTelas()
    {
        if (!pronto) return;
        List<IntPtr> mons = Monitores();
        StringBuilder sb = new StringBuilder("{\"monitores\":[");
        for (int i = 0; i < mons.Count; i++) {
            MONITORINFO mi = Info(mons[i]); RECT r = mi.rcMonitor;
            if (i > 0) sb.Append(',');
            sb.AppendFormat("{{\"d\":{0},\"x\":{1},\"y\":{2},\"w\":{3},\"h\":{4},\"p\":{5}}}",
                J(mi.szDevice), r.Left, r.Top, r.Right - r.Left, r.Bottom - r.Top, (mi.dwFlags & 1) != 0 ? "true" : "false");
        }
        sb.AppendFormat("],\"monitor\":{0},\"lado\":\"{1}\",\"largura\":{2}}}",
            J(Info(monitor).szDevice), direita ? "direita" : "esquerda", largura);
        try { web.CoreWebView2.PostWebMessageAsString(sb.ToString()); } catch { }
    }

    void AplicarConfig(string texto)
    {
        string[] p = texto.Split('|');
        if (p.Length < 3) return;
        monitorEscolhido = p[0];
        direita = p[1] == "direita";
        int l; if (int.TryParse(p[2], out l)) largura = Math.Max(300, Math.Min(800, l));
        SalvarConfig();
        Log("engrenagem: monitor " + monitorEscolhido + ", " + p[1] + ", " + largura + " px");
        if (!escondido) { Liberar(); Registrar(); Reservar(); } // muda de lugar na hora
        if (quadro != null && quadroAberto && !quadroAnimando) quadro.Bounds = RetQuadro(); // quadro acompanha o monitor escolhido
        EnviarTelas();
    }

    // ---------- monitor e reserva da faixa ----------
    static MONITORINFO Info(IntPtr m)
    {
        MONITORINFO mi = new MONITORINFO(); mi.cbSize = Marshal.SizeOf(typeof(MONITORINFO));
        GetMonitorInfo(m, ref mi); return mi;
    }

    static List<IntPtr> Monitores()
    {
        List<IntPtr> mons = new List<IntPtr>();
        EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, delegate(IntPtr m, IntPtr dc, ref RECT r, IntPtr d) { mons.Add(m); return true; }, IntPtr.Zero);
        mons.Sort(delegate(IntPtr a, IntPtr b) { return Info(a).rcMonitor.Left.CompareTo(Info(b).rcMonitor.Left); }); // da esquerda para a direita
        return mons;
    }

    IntPtr EscolherMonitor()
    {
        List<IntPtr> mons = Monitores();
        // monitor escolhido na engrenagem, se ainda estiver conectado
        foreach (IntPtr m in mons) if (monitorEscolhido != "" && Info(m).szDevice == monitorEscolhido) return m;
        int idx;
        if (int.TryParse(monitorPref, out idx) && idx >= 0 && idx < mons.Count) return mons[idx];
        IntPtr melhor = IntPtr.Zero, principal = IntPtr.Zero; int maior = -1;
        foreach (IntPtr m in mons) {
            MONITORINFO mi = Info(m);
            if ((mi.dwFlags & 1) != 0) { principal = m; continue; }
            int w = mi.rcMonitor.Right - mi.rcMonitor.Left;
            if (w > maior) { maior = w; melhor = m; }
        }
        return melhor != IntPtr.Zero ? melhor : principal;
    }

    void Registrar()
    {
        if (registrado) return;
        SHAppBarMessage(ABM_NEW, ref abd); registrado = true;
    }

    void Liberar()
    {
        if (!registrado) return;
        SHAppBarMessage(ABM_REMOVE, ref abd); registrado = false;
    }

    void Reservar()
    {
        monitor = EscolherMonitor();
        RECT mon = Info(monitor).rcMonitor;
        abd.uEdge = direita ? ABE_RIGHT : ABE_LEFT;
        abd.rc.Top = mon.Top; abd.rc.Bottom = mon.Bottom;
        if (direita) { abd.rc.Right = mon.Right; abd.rc.Left = mon.Right - largura; }
        else         { abd.rc.Left = mon.Left;   abd.rc.Right = mon.Left + largura; }
        SHAppBarMessage(ABM_QUERYPOS, ref abd);
        if (direita) abd.rc.Left = abd.rc.Right - largura; else abd.rc.Right = abd.rc.Left + largura;
        SHAppBarMessage(ABM_SETPOS, ref abd);
        faixa = abd.rc;
        Log(string.Format("monitor=({0},{1})-({2},{3}) faixa=({4},{5})-({6},{7})",
            mon.Left, mon.Top, mon.Right, mon.Bottom, faixa.Left, faixa.Top, faixa.Right, faixa.Bottom));
        if (!animando && !escondido) Posicionar(1);
    }

    // 1 = no lugar, 0 = fora da tela pela esquerda
    void Posicionar(double aberto)
    {
        int w = faixa.Right - faixa.Left, h = faixa.Bottom - faixa.Top;
        int fora = (int)Math.Round((w + 30) * (1 - aberto));
        int x = direita ? faixa.Left + fora : faixa.Left - fora; // sai pela borda do lado escolhido
        IntPtr z = cedido ? IntPtr.Zero : TOPMOST;
        // recorta no limite do monitor: ao deslizar, o painel nao aparece no monitor vizinho
        RECT mon = Info(monitor).rcMonitor;
        if (aberto >= 1) SetWindowRgn(Handle, IntPtr.Zero, true);
        else SetWindowRgn(Handle, CreateRectRgn(Math.Max(0, mon.Left - x), 0, Math.Max(0, Math.Min(w, mon.Right - x)), h), true);
        SetWindowPos(Handle, z, x, faixa.Top, w, h, NOACTIVATE | (cedido ? NOZORDER : 0));
    }

    // ---------- Win+Espaco ----------
    // Win+Espaco: painel de demandas | Win+F: quadro de obras
    int teclaPresa; // tecla (0x20 ou 0x46) cuja combinacao com Win foi capturada e ainda nao foi solta
    IntPtr Gancho(int code, IntPtr wParam, IntPtr lParam)
    {
        int vk = code >= 0 ? Marshal.ReadInt32(lParam) : 0;
        if (vk == 0x20 || vk == 0x46) {
            int msg = wParam.ToInt32();
            bool winPreso = (GetAsyncKeyState(0x5B) & 0x8000) != 0 || (GetAsyncKeyState(0x5C) & 0x8000) != 0;
            if ((msg == 0x100 || msg == 0x104) && winPreso) {
                if (teclaPresa != vk) {
                    teclaPresa = vk;
                    // tecla neutra: impede o menu Iniciar de abrir quando o Win for solto
                    keybd_event(0xE8, 0, 0, UIntPtr.Zero); keybd_event(0xE8, 0, 2, UIntPtr.Zero);
                    BeginInvoke(new MethodInvoker(vk == 0x20 ? (MethodInvoker)Alternar : AlternarQuadro));
                }
                return new IntPtr(1); // engole: o Windows nao troca o idioma nem abre o Hub de Comentarios
            }
            if ((msg == 0x101 || msg == 0x105) && teclaPresa == vk) { teclaPresa = 0; return new IntPtr(1); }
        }
        return CallNextHookEx(gancho, code, wParam, lParam);
    }

    void Alternar()
    {
        if (animando) return;
        if (!escondido) {
            escondido = true;
            Animar(false);                 // a faixa so e liberada no fim
        } else {
            escondido = false;
            Registrar(); Reservar();       // reserva a faixa de novo
            Posicionar(0);
            if (!Visible) Show();
            Activate();
            if (pronto) { try { web.CoreWebView2.ExecuteScriptAsync("window.entrar && entrar()"); } catch { } }
            Animar(true);
        }
        Log(escondido ? "atalho: painel escondido" : "atalho: painel visivel");
    }

    // ---------- quadro de obras (Win+F): janela grande que sai de dentro do painel ----------
    class JanelaQuadro : Form {
        protected override CreateParams CreateParams {
            get { CreateParams cp = base.CreateParams; cp.ExStyle |= 0x80; cp.ClassStyle |= 0x20000; return cp; } // sem barra de tarefas, com sombra
        }
    }
    JanelaQuadro quadro; WebView2 webQ; bool quadroPronto, quadroAberto, quadroAnimando, quadroAbrindo;
    Timer qAnim; DateTime qInicio; Rectangle qDe, qPara;
    const double QUADRO_MS = 380;

    Rectangle RetPainel() { return new Rectangle(faixa.Left, faixa.Top, faixa.Right - faixa.Left, faixa.Bottom - faixa.Top); }

    Rectangle RetQuadro()
    {
        RECT m = Info(monitor).rcMonitor; // tela inteira do monitor do painel, por cima do painel
        return new Rectangle(m.Left, m.Top, m.Right - m.Left, m.Bottom - m.Top);
    }

    void CriarQuadro()
    {
        quadro = new JanelaQuadro();
        quadro.FormBorderStyle = FormBorderStyle.None;
        quadro.ShowInTaskbar = false; quadro.TopMost = true;
        quadro.StartPosition = FormStartPosition.Manual;
        quadro.BackColor = BackColor; quadro.Text = "Quadro de RT";
        webQ = new WebView2(); webQ.Dock = DockStyle.Fill; webQ.DefaultBackgroundColor = BackColor;
        webQ.CreationProperties = Opcoes();
        quadro.Controls.Add(webQ);
        quadro.Bounds = RetPainel();
        quadro.Load += async delegate {
            int canto = 1; DwmSetWindowAttribute(quadro.Handle, 33, ref canto, 4); // cantos retos: ocupa a tela toda
            try {
                await webQ.EnsureCoreWebView2Async(null);
                CoreWebView2Settings s = webQ.CoreWebView2.Settings;
                s.AreDefaultContextMenusEnabled = false; s.AreDevToolsEnabled = false; s.IsStatusBarEnabled = false;
                s.IsZoomControlEnabled = false; s.AreBrowserAcceleratorKeysEnabled = false;
                s.IsPasswordAutosaveEnabled = false; s.IsGeneralAutofillEnabled = false;
                webQ.CoreWebView2.WebMessageReceived += MensagemDoQuadro;
                string obras = System.IO.Path.Combine(System.IO.Path.GetDirectoryName(html), "obras.html");
                webQ.CoreWebView2.Navigate(new Uri(obras).AbsoluteUri);
                quadroPronto = true;
                Log("quadro de obras aberto");
            } catch (Exception ex) { Log("ERRO ao iniciar o quadro: " + ex.Message); }
        };
    }

    void MensagemDoQuadro(object sender, CoreWebView2WebMessageReceivedEventArgs e)
    {
        string m = "";
        try { m = e.TryGetWebMessageAsString(); } catch { }
        if (m == "fechar") { if (quadroAberto) AlternarQuadro(); return; }
        if (m == "quadro?") {
            string[] q = LerQuadro();
            string json = "{\"usuario\":" + J(Environment.UserName) + (q[0] != "" ? ",\"quadro\":" + J(q[0]) : "") + (q[1] != "" ? ",\"nome\":" + J(q[1]) : "") + "}";
            try { webQ.CoreWebView2.PostWebMessageAsString(json); } catch { }
            return;
        }
        if (m.StartsWith("backup:obras:")) { Backup("obras", m.Substring(13)); return; }
        if (m == "obrasLocal?") {
            string b = LerBackup("obras");
            try { webQ.CoreWebView2.PostWebMessageAsString("{\"obrasLocal\":" + (b ?? "null") + "}"); } catch { }
            return;
        }
        if (m == "versao?") { if (versaoNova != null) AvisarAtualizacao(); VerificarAtualizacao(); return; }
        if (m == "atualizar") { Atualizar(); return; }
        if (m == "tema:escuro" || m == "tema:claro") {
            Color c = m == "tema:escuro" ? FUNDO_ESCURO : FUNDO_CLARO;
            quadro.BackColor = c; webQ.DefaultBackgroundColor = c;
        }
    }

    // ---------- dados locais: codigo do quadro e backups (nunca tocados pela atualizacao) ----------
    static string[] LerQuadro()
    {
        string[] r = new string[] { "", "" };
        try {
            string f = System.IO.Path.Combine(dadosPath, "quadro.txt");
            if (System.IO.File.Exists(f)) {
                string[] l = System.IO.File.ReadAllLines(f);
                if (l.Length > 0) r[0] = l[0].Trim();
                if (l.Length > 1) r[1] = l[1].Trim();
            }
        } catch { }
        return r;
    }

    static void GravarSeguro(string caminho, string texto)
    {
        string tmp = caminho + ".tmp";
        System.IO.File.WriteAllText(tmp, texto, new UTF8Encoding(false));
        System.IO.File.Copy(tmp, caminho, true);
        System.IO.File.Delete(tmp);
    }

    // copia sempre atualizada + uma por dia (ultimos 30 dias)
    static void Backup(string tipo, string json)
    {
        try {
            json = (json ?? "").Trim();
            if (json.Length < 2 || (json[0] != '[' && json[0] != '{')) return;
            string dir = System.IO.Path.Combine(dadosPath, "backups");
            System.IO.Directory.CreateDirectory(dir);
            string atual = System.IO.Path.Combine(dir, tipo + ".json");
            string anterior = System.IO.File.Exists(atual) ? System.IO.File.ReadAllText(atual).Trim() : "";
            // nunca grava uma copia mais velha por cima de uma mais nova
            long novoEm = SalvoEm(json), atualEm = SalvoEm(anterior);
            if (novoEm > 0 && atualEm > novoEm) { Log("backup de " + tipo + " ignorado: copia mais antiga que a ja salva"); return; }
            // lista ficou vazia: guarda antes a versao anterior com conteudo, por seguranca
            bool vazio = json == "[]" || json == "{}" || json.Contains("\"tarefas\":[]") || (json.Contains("\"cards\":{}") && json.Contains("\"clientes\":{}"));
            bool antVazio = anterior.Length <= 2 || anterior.Contains("\"tarefas\":[]") || (anterior.Contains("\"cards\":{}") && anterior.Contains("\"clientes\":{}"));
            if (vazio && System.IO.File.Exists(atual) && !antVazio)
                System.IO.File.Copy(atual, System.IO.Path.Combine(dir, tipo + "-antes-de-esvaziar-" + DateTime.Now.ToString("yyyy-MM-dd-HHmmss") + ".json"), true);
            GravarSeguro(atual, json);
            GravarSeguro(System.IO.Path.Combine(dir, tipo + "-" + DateTime.Now.ToString("yyyy-MM-dd") + ".json"), json);
            string[] dias = System.IO.Directory.GetFiles(dir, tipo + "-????-??-??.json");
            Array.Sort(dias);
            for (int i = 0; i < dias.Length - 30; i++) System.IO.File.Delete(dias[i]);
        } catch (Exception e) { Log("backup de " + tipo + " falhou: " + e.Message); }
    }

    static long SalvoEm(string json)
    {
        System.Text.RegularExpressions.Match m = System.Text.RegularExpressions.Regex.Match(json ?? "", "\"salvoEm\"\\s*:\\s*(\\d+)");
        long v; return m.Success && long.TryParse(m.Groups[1].Value, out v) ? v : 0;
    }

    static string LerBackup(string tipo)
    {
        try {
            string f = System.IO.Path.Combine(System.IO.Path.Combine(dadosPath, "backups"), tipo + ".json");
            return System.IO.File.Exists(f) ? System.IO.File.ReadAllText(f).Trim() : null;
        } catch { return null; }
    }

    // ---------- atualizacao automatica (arquivos do programa vindos do GitHub) ----------
    const string FONTE = "https://raw.githubusercontent.com/levybezerradomingos00-a11y/painel-demandas/main/";
    string versaoNova, versaoNovaTexto; bool verificando, atualizando;

    static string VersaoLocal()
    {
        try {
            string t = System.IO.File.ReadAllText(System.IO.Path.Combine(appPath, "versao.json"));
            System.Text.RegularExpressions.Match m = System.Text.RegularExpressions.Regex.Match(t, "\"versao\"\\s*:\\s*\"([0-9.]+)\"");
            return m.Success ? m.Groups[1].Value : "0.0.0";
        } catch { return "0.0.0"; }
    }

    static System.Net.WebClient Cliente()
    {
        System.Net.ServicePointManager.SecurityProtocol |= (System.Net.SecurityProtocolType)3072; // TLS 1.2
        System.Net.WebClient w = new System.Net.WebClient();
        w.Headers["Cache-Control"] = "no-cache";
        return w;
    }

    static string Sha256(byte[] dados)
    {
        using (System.Security.Cryptography.SHA256 s = System.Security.Cryptography.SHA256.Create())
            return BitConverter.ToString(s.ComputeHash(dados)).Replace("-", "").ToLowerInvariant();
    }

    void VerificarAtualizacao()
    {
        if (verificando || atualizando) return;
        verificando = true;
        System.Threading.ThreadPool.QueueUserWorkItem(delegate {
            try {
                string t;
                using (System.Net.WebClient w = Cliente()) t = w.DownloadString(FONTE + "versao.json?t=" + DateTime.UtcNow.Ticks);
                System.Text.RegularExpressions.Match m = System.Text.RegularExpressions.Regex.Match(t, "\"versao\"\\s*:\\s*\"([0-9.]+)\"");
                if (m.Success && new Version(m.Groups[1].Value) > new Version(VersaoLocal())) {
                    BeginInvoke(new MethodInvoker(delegate { versaoNova = m.Groups[1].Value; versaoNovaTexto = t; AvisarAtualizacao(); }));
                }
            } catch (Exception e) { Log("verificar atualizacao: " + e.Message); }
            finally { verificando = false; }
        });
    }

    void AvisarAtualizacao()
    {
        if (versaoNova == null || webQ == null || webQ.CoreWebView2 == null) return;
        try { webQ.CoreWebView2.PostWebMessageAsString("{\"atualizacao\":" + J(versaoNova) + "}"); } catch { }
    }

    // baixa so os arquivos que mudaram, confere cada um e so entao troca; os dados nunca sao tocados
    void Atualizar()
    {
        if (atualizando || versaoNovaTexto == null) return;
        atualizando = true;
        try { webQ.CoreWebView2.PostWebMessageAsString("{\"atualizando\":true}"); } catch { }
        string remoto = versaoNovaTexto, versao = versaoNova;
        Log("atualizando para a versao " + versao);
        System.Threading.ThreadPool.QueueUserWorkItem(delegate {
            List<string> trocar = new List<string>();
            try {
                // copia extra dos dados antes de qualquer coisa
                string dir = System.IO.Path.Combine(dadosPath, "backups");
                System.IO.Directory.CreateDirectory(dir);
                foreach (string tipo in new string[] { "demandas", "obras" }) {
                    string f = System.IO.Path.Combine(dir, tipo + ".json");
                    if (System.IO.File.Exists(f)) System.IO.File.Copy(f, System.IO.Path.Combine(dir, "antes-da-versao-" + versao + "-" + tipo + ".json"), true);
                }
                System.Text.RegularExpressions.MatchCollection arqs = System.Text.RegularExpressions.Regex.Matches(remoto, "\"([A-Za-z0-9_./-]+)\"\\s*:\\s*\"([0-9a-f]{64})\"");
                using (System.Net.WebClient w = Cliente()) {
                    foreach (System.Text.RegularExpressions.Match a in arqs) {
                        string nome = a.Groups[1].Value, hash = a.Groups[2].Value;
                        if (nome.Contains("..")) throw new Exception("nome de arquivo invalido: " + nome);
                        string local = System.IO.Path.Combine(appPath, nome.Replace('/', '\\'));
                        if (System.IO.File.Exists(local) && Sha256(System.IO.File.ReadAllBytes(local)) == hash) continue;
                        byte[] novo = w.DownloadData(FONTE + nome + "?t=" + DateTime.UtcNow.Ticks);
                        if (Sha256(novo) != hash) throw new Exception("arquivo baixado nao confere: " + nome);
                        string destino = nome.StartsWith("lib/")
                            ? System.IO.Path.Combine(System.IO.Path.Combine(appPath, "lib-novo"), nome.Substring(4))
                            : local + ".novo";
                        System.IO.Directory.CreateDirectory(System.IO.Path.GetDirectoryName(destino));
                        System.IO.File.WriteAllBytes(destino, novo);
                        if (!nome.StartsWith("lib/")) trocar.Add(local);
                    }
                }
                foreach (string local in trocar) { System.IO.File.Copy(local + ".novo", local, true); System.IO.File.Delete(local + ".novo"); }
                GravarSeguro(System.IO.Path.Combine(appPath, "versao.json"), remoto);
                Log("atualizacao " + versao + " instalada (" + trocar.Count + " arquivos); reiniciando");
                BeginInvoke(new MethodInvoker(Reiniciar));
            } catch (Exception e) {
                foreach (string local in trocar) { try { System.IO.File.Delete(local + ".novo"); } catch { } }
                Log("ERRO na atualizacao: " + e.Message);
                BeginInvoke(new MethodInvoker(delegate {
                    atualizando = false;
                    try { webQ.CoreWebView2.PostWebMessageAsString("{\"erroAtualizacao\":" + J(e.Message) + "}"); } catch { }
                }));
            }
        });
    }

    // abre a versao nova; ela mesma encerra esta
    void Reiniciar()
    {
        string ps1 = System.IO.Path.Combine(appPath, "abrir-painel.ps1");
        ProcessStartInfo psi = new ProcessStartInfo("powershell.exe",
            "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + ps1 + "\"");
        psi.UseShellExecute = false; psi.CreateNoWindow = true;
        Process.Start(psi);
    }

    void ScriptQuadro(string js) { if (quadroPronto) { try { webQ.CoreWebView2.ExecuteScriptAsync(js); } catch { } } }

    void AlternarQuadro()
    {
        if (quadroAnimando) return;
        if (quadro == null) CriarQuadro();
        if (!quadroAberto) {
            quadroAberto = true;
            ScriptQuadro("window.preparar && preparar()");
            quadro.Bounds = RetPainel();
            if (!quadro.Visible) quadro.Show();
            quadro.TopMost = true; quadro.Activate();
            AnimarQuadro(RetPainel(), RetQuadro(), true);
        } else {
            quadroAberto = false;
            ScriptQuadro("window.sair && sair()");
            Rectangle de = quadro.Bounds;
            Timer espera = new Timer(); espera.Interval = 120; // conteudo some antes de a janela encolher
            espera.Tick += delegate { espera.Stop(); espera.Dispose(); AnimarQuadro(de, RetPainel(), false); };
            quadroAnimando = true; espera.Start();
        }
        Log(quadroAberto ? "Win+F: quadro aberto" : "Win+F: quadro fechado");
    }

    void AnimarQuadro(Rectangle de, Rectangle para, bool abrindo)
    {
        qDe = de; qPara = para; quadroAbrindo = abrindo; quadroAnimando = true; qInicio = DateTime.Now;
        if (qAnim == null) { qAnim = new Timer(); qAnim.Interval = 8; qAnim.Tick += delegate { PassoQuadro(); }; }
        qAnim.Start();
    }

    void PassoQuadro()
    {
        double t = Math.Min(1, (DateTime.Now - qInicio).TotalMilliseconds / QUADRO_MS);
        double p = quadroAbrindo ? 1 - Math.Pow(1 - t, 4) : t * t * (3 - 2 * t);
        quadro.Bounds = new Rectangle(
            (int)Math.Round(qDe.X + (qPara.X - qDe.X) * p), (int)Math.Round(qDe.Y + (qPara.Y - qDe.Y) * p),
            (int)Math.Round(qDe.Width + (qPara.Width - qDe.Width) * p), (int)Math.Round(qDe.Height + (qPara.Height - qDe.Height) * p));
        if (t < 1) return;
        qAnim.Stop(); quadroAnimando = false;
        if (quadroAbrindo) ScriptQuadro("window.entrar && entrar()");
        else quadro.Hide();
    }

    void Animar(bool mostrar)
    {
        animMostrando = mostrar; animando = true; animInicio = DateTime.Now;
        if (anim == null) { anim = new Timer(); anim.Interval = 8; anim.Tick += delegate { Passo(); }; }
        anim.Start();
    }

    void Passo()
    {
        double t = Math.Min(1, (DateTime.Now - animInicio).TotalMilliseconds / ANIM_MS);
        // entrada: rapida e pousando suave; saida: comeca suave e acelera
        double p = animMostrando ? 1 - Math.Pow(1 - t, 4) : 1 - Math.Pow(t, 3);
        Posicionar(p);
        if (t < 1) return;
        anim.Stop(); animando = false;
        if (!animMostrando) { Liberar(); Hide(); } // escondido de verdade: nada fica em outro monitor
    }

    // ---------- tela cheia (ex.: video): o painel sai da frente ate ela acabar ----------
    void TratarTelaCheia()
    {
        RECT mon = Info(monitor).rcMonitor;
        IntPtr fg = GetForegroundWindow();
        bool telaCheia = false;
        if (fg != IntPtr.Zero && GetAncestor(fg, 2) != Handle && IsWindowVisible(fg)) {
            StringBuilder c = new StringBuilder(64); GetClassName(fg, c, 64);
            string cls = c.ToString();
            RECT r; GetWindowRect(fg, out r);
            telaCheia = cls != "Progman" && cls != "WorkerW" && cls != "Shell_TrayWnd" && cls != "Shell_SecondaryTrayWnd" &&
                        r.Left <= mon.Left && r.Top <= mon.Top && r.Right >= mon.Right && r.Bottom >= mon.Bottom;
        }
        if (telaCheia && !cedido) {
            cedido = true; Log("tela cheia: painel saiu da frente");
            SetWindowPos(Handle, NOTOPMOST, 0, 0, 0, 0, NOSIZE | NOMOVE | NOACTIVATE);
            SetWindowPos(Handle, BOTTOM, 0, 0, 0, 0, NOSIZE | NOMOVE | NOACTIVATE);
        } else if (!telaCheia && cedido) {
            cedido = false;
            SetWindowPos(Handle, TOPMOST, 0, 0, 0, 0, NOSIZE | NOMOVE | NOACTIVATE);
        }
    }

    int segundos;
    void Verificar()
    {
        if (!escondido && !animando) {
            TratarTelaCheia();
            // corrige se algo tirou o painel do lugar
            RECT r; GetWindowRect(Handle, out r);
            if (r.Left != faixa.Left || r.Top != faixa.Top || r.Right != faixa.Right || r.Bottom != faixa.Bottom) Posicionar(1);
        }
        if (++segundos % 60 == 0) MedirUso();
        if (segundos % 10800 == 30) VerificarAtualizacao(); // ~a cada 3 horas
    }

    // ---------- consumo (anotado no diagnostico) ----------
    DateTime ultimaMedida; TimeSpan ultimaCpu;
    void MedirUso()
    {
        try {
            long mem = 0; TimeSpan cpu = TimeSpan.Zero; int n = 0;
            List<Process> procs = new List<Process>();
            procs.Add(Process.GetCurrentProcess());
            using (System.Management.ManagementObjectSearcher q = new System.Management.ManagementObjectSearcher(
                "SELECT ProcessId FROM Win32_Process WHERE Name='msedgewebview2.exe' AND CommandLine LIKE '%PainelDemandas%'"))
                foreach (System.Management.ManagementObject o in q.Get())
                    try { procs.Add(Process.GetProcessById(Convert.ToInt32(o["ProcessId"]))); } catch { }
            foreach (Process p in procs) { try { p.Refresh(); mem += p.PrivateMemorySize64; cpu += p.TotalProcessorTime; n++; } catch { } }
            string cpuTxt = "";
            if (ultimaMedida != DateTime.MinValue) {
                double pct = (cpu - ultimaCpu).TotalMilliseconds / (DateTime.Now - ultimaMedida).TotalMilliseconds / Environment.ProcessorCount * 100;
                cpuTxt = string.Format(" | CPU media: {0:0.0}%", Math.Max(0, pct));
            }
            ultimaMedida = DateTime.Now; ultimaCpu = cpu;
            Log(string.Format("uso: {0} processos | memoria {1} MB{2}", n, mem / 1048576, cpuTxt));
        } catch (Exception e) { Log("uso: nao foi possivel medir (" + e.Message + ")"); }
    }

    public static void Log(string linha)
    {
        if (logPath == null) return;
        try { System.IO.File.AppendAllText(logPath, DateTime.Now.ToString("HH:mm:ss ") + linha + "\r\n"); } catch { }
    }

    // ---------- mensagens do Windows ----------
    protected override void WndProc(ref Message m)
    {
        if (registrado && m.Msg == (int)cbMsg && m.WParam.ToInt32() == ABN_POSCHANGED && !escondido && !animando)
            BeginInvoke(new MethodInvoker(Reservar));
        if (m.Msg == 0x007E && !escondido) BeginInvoke(new MethodInvoker(Reservar)); // monitores/resolucao mudaram
        if (m.Msg == 0x0011 || m.Msg == 0x0016) Liberar();                          // desligando / saindo
        base.WndProc(ref m);
    }

    protected override void OnFormClosed(FormClosedEventArgs e)
    {
        if (gancho != IntPtr.Zero) { UnhookWindowsHookEx(gancho); gancho = IntPtr.Zero; }
        Liberar();
        base.OnFormClosed(e);
    }
}
'@

[Painel]::logPath = $log
[Painel]::configPath = Join-Path $dados 'config.txt'
[Painel]::dadosPath = $dados
[Painel]::appPath = $pasta
Anotar "abrindo painel"
try {
    [Painel]::Rodar($Largura, [string]$Monitor, $html, $perfil)
} finally {
    $mutex.ReleaseMutex()
}
