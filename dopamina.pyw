import customtkinter as ctk
import pygetwindow as gw
import pyautogui
import threading
import time
import sys
import json
from tkinter import filedialog
from PIL import Image
from pystray import MenuItem as item
import pystray

# --- CONFIGURAÇÃO INICIAL ---
CONFIG_FILE = "sites_config.json"
SITES_PALAVRAS_CHAVE_PADRAO = [
    "youtube", "facebook", "instagram", "twitter", "tiktok", "reddit",
    "senac", "kabum", "kabun", "senai", "shopee", "amazon",
    "mercado livre", "mercadolivre",
]

# --- FUNÇÕES DE DADOS ---
def carregar_sites():
    """Carrega os sites do arquivo JSON. Se não existir, cria com valores padrão."""
    try:
        with open(CONFIG_FILE, 'r', encoding='utf-8') as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        salvar_sites(SITES_PALAVRAS_CHAVE_PADRAO)
        return SITES_PALAVRAS_CHAVE_PADRAO

def salvar_sites(sites):
    """Salva a lista de sites no arquivo JSON."""
    with open(CONFIG_FILE, 'w', encoding='utf-8') as f:
        json.dump(sites, f, indent=4)

# --- CLASSE PRINCIPAL DA APLICAÇÃO ---
class App(ctk.CTk):
    def __init__(self):
        super().__init__()

        # --- CONFIGURAÇÃO DA JANELA ---
        self.title("Monitor de Foco (Sem Admin)")
        self.geometry("500x650")
        self.grid_columnconfigure(0, weight=1)
        self.grid_rowconfigure(1, weight=1)
        self.icon = None
        self.icon_thread = None

        ctk.set_appearance_mode("dark")
        ctk.set_default_color_theme("green")

        # --- VARIÁVEIS DE CONTROLE ---
        self.monitoring_active = False
        self.monitor_thread = None

        # --- WIDGETS ---
        self.main_frame = ctk.CTkFrame(self)
        self.main_frame.grid(row=0, column=0, rowspan=4, padx=20, pady=20, sticky="nsew")
        self.main_frame.grid_columnconfigure(0, weight=1)
        self.main_frame.grid_rowconfigure(1, weight=1)

        self.label_info = ctk.CTkLabel(
            self.main_frame,
            text="Palavras-chave a monitorar (uma por linha):",
            font=ctk.CTkFont(size=16, weight="bold")
        )
        self.label_info.grid(row=0, column=0, padx=15, pady=(15, 10))

        self.textbox_sites = ctk.CTkTextbox(self.main_frame, font=ctk.CTkFont(size=14))
        self.textbox_sites.grid(row=1, column=0, padx=15, pady=5, sticky="nsew")
        self.sites_atuais = carregar_sites()
        self.textbox_sites.insert("0.0", "\n".join(self.sites_atuais))

        # Frame para botões de controle
        self.control_frame = ctk.CTkFrame(self.main_frame, fg_color="transparent")
        self.control_frame.grid(row=2, column=0, pady=15)
        self.control_frame.grid_columnconfigure((0, 1), weight=1)
        
        # Botão para Importar
        self.button_import = ctk.CTkButton(
            self.control_frame,
            text="Importar JSON",
            command=self.importar_config,
            height=40
        )
        self.button_import.grid(row=0, column=0, padx=5)

        # Botão para Exportar
        self.button_export = ctk.CTkButton(
            self.control_frame,
            text="Exportar JSON",
            command=self.exportar_config,
            height=40
        )
        self.button_export.grid(row=0, column=1, padx=5)

        # Botão para iniciar/parar o monitoramento
        self.button_toggle = ctk.CTkButton(
            self.main_frame,
            text="Iniciar Monitoramento",
            command=self.toggle_monitoring,
            font=ctk.CTkFont(size=14, weight="bold"),
            height=40
        )
        self.button_toggle.grid(row=3, column=0, padx=15, pady=10)

        # Rótulo de status
        self.label_status = ctk.CTkLabel(
            self.main_frame,
            text="Status: Inativo",
            font=ctk.CTkFont(size=14)
        )
        self.label_status.grid(row=4, column=0, padx=15, pady=(5, 15))
        
        # Garante que os threads serão finalizados ao fechar
        self.protocol("WM_DELETE_WINDOW", self.hide_to_tray)

    def get_keywords_from_textbox(self):
        """Pega as palavras-chave da caixa de texto e as retorna como uma lista."""
        return [k.lower() for k in self.textbox_sites.get("1.0", "end-1c").splitlines() if k.strip()]

    def toggle_monitoring(self):
        """Inicia ou para o processo de monitoramento."""
        if self.monitoring_active:
            # Para o monitoramento
            self.monitoring_active = False
            self.button_toggle.configure(text="Iniciar Monitoramento", fg_color=("#3B8ED0", "#1F6AA5"))
            self.label_status.configure(text="Status: Inativo", text_color="gray")
            self.textbox_sites.configure(state="normal")
            self.button_import.configure(state="normal")
            self.button_export.configure(state="normal")
            if self.monitor_thread:
                self.monitor_thread.join()
        else:
            # Inicia o monitoramento
            self.monitoring_active = True
            self.sites_atuais = self.get_keywords_from_textbox()
            salvar_sites(self.sites_atuais) # Salva a configuração atual
            self.button_toggle.configure(text="Parar Monitoramento", fg_color="#D32F2F", hover_color="#B71C1C")
            self.label_status.configure(text="Status: Ativo e vigiando...", text_color="#4CAF50")
            self.textbox_sites.configure(state="disabled")
            self.button_import.configure(state="disabled")
            self.button_export.configure(state="disabled")

            self.monitor_thread = threading.Thread(target=self.run_monitor, daemon=True)
            self.monitor_thread.start()
            self.hide_to_tray() # Opcional: esconder automaticamente ao iniciar

    def run_monitor(self):
        """Função que roda no thread, verificando a janela ativa."""
        while self.monitoring_active:
            try:
                active_window = gw.getActiveWindow()
                if active_window:
                    title = active_window.title.lower()
                    for keyword in self.sites_atuais:
                        if keyword in title:
                            # Atualiza a interface gráfica no thread principal
                            self.after(0, lambda: self.label_status.configure(text=f"Distração detectada: '{keyword}'! Fechando...", text_color="orange"))
                            
                            if sys.platform == "darwin": # macOS
                                pyautogui.hotkey('command', 'w')
                            else: # Windows/Linux
                                pyautogui.hotkey('ctrl', 'w')
                            
                            time.sleep(1)
                            # Volta o status para "Ativo"
                            self.after(0, lambda: self.label_status.configure(text="Status: Ativo e vigiando...", text_color="#4CAF50"))
                            break
            except Exception as e:
                print(f"Erro menor no monitor: {e}")

            time.sleep(1.5)
        print("Thread de monitoramento finalizado.")

    def importar_config(self):
        """Abre o explorador de arquivos para importar um arquivo JSON."""
        filepath = filedialog.askopenfilename(
            title="Importar Configuração",
            filetypes=[("Arquivos JSON", "*.json"), ("Todos os arquivos", "*.*")]
        )
        if filepath:
            try:
                with open(filepath, 'r', encoding='utf-8') as f:
                    sites_importados = json.load(f)
                    if isinstance(sites_importados, list):
                        self.textbox_sites.delete("1.0", "end")
                        self.textbox_sites.insert("0.0", "\n".join(sites_importados))
                        salvar_sites(sites_importados) # Salva como nova configuração padrão
                    else:
                        print("Erro: O arquivo JSON não contém uma lista.")
            except Exception as e:
                print(f"Falha ao importar arquivo: {e}")

    def exportar_config(self):
        """Abre o explorador de arquivos para salvar a configuração atual."""
        filepath = filedialog.asksaveasfilename(
            title="Exportar Configuração",
            defaultextension=".json",
            filetypes=[("Arquivos JSON", "*.json")]
        )
        if filepath:
            sites_para_exportar = self.get_keywords_from_textbox()
            with open(filepath, 'w', encoding='utf-8') as f:
                json.dump(sites_para_exportar, f, indent=4)
    
    # --- FUNÇÕES DO SYSTEM TRAY ---
    def create_image(self):
        """Cria uma imagem simples para o ícone da bandeja."""
        width = 64
        height = 64
        color1 = (50, 200, 50) # Verde
        color2 = (20, 80, 20)  # Verde Escuro
        image = Image.new('RGB', (width, height), color2)
        # Desenha um "F" de Foco
        for x in range(20, 45):
            for y in range(15, 25): image.putpixel((x, y), color1)
        for x in range(20, 30):
            for y in range(25, 50): image.putpixel((x, y), color1)
        for x in range(20, 40):
            for y in range(30, 40): image.putpixel((x, y), color1)
        return image
    
    def show_window(self):
        """Mostra a janela e para o ícone da bandeja."""
        if self.icon:
            self.icon.stop()
        self.deiconify() # Mostra a janela novamente
        self.lift()
        self.focus_force()

    def on_quit(self):
        """Função para encerrar o programa a partir do ícone da bandeja."""
        if self.icon:
            self.icon.stop()
        self.monitoring_active = False # Para o thread de monitoramento
        self.destroy() # Fecha a aplicação

    def setup_tray_icon(self):
        """Configura e inicia o ícone na bandeja do sistema."""
        image = self.create_image()
        menu = (item('Abrir Monitor', self.show_window), item('Sair', self.on_quit))
        self.icon = pystray.Icon("monitor_foco", image, "Monitor de Foco", menu)
        self.icon.run()

    def hide_to_tray(self):
        """Esconde a janela e inicia o ícone da bandeja em um thread separado."""
        self.withdraw() # Esconde a janela principal
        if not self.icon_thread or not self.icon_thread.is_alive():
            self.icon_thread = threading.Thread(target=self.setup_tray_icon, daemon=True)
            self.icon_thread.start()

# --- PONTO DE ENTRADA ---
if __name__ == "__main__":
    app = App()
    app.mainloop()