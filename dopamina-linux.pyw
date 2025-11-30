#!/usr/bin/env python3
"""
Monitor de Foco para Linux
Versão GTK - Monitora e fecha janelas com palavras-chave específicas
"""

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("AppIndicator3", "0.1")
from gi.repository import Gtk, Gdk, GLib, AppIndicator3

import subprocess
import threading
import time
import json
import os
from pathlib import Path

# --- CONFIGURAÇÃO INICIAL ---
CONFIG_FILE = "sites_config.json"
SITES_PALAVRAS_CHAVE_PADRAO = [
    "youtube",
    "facebook",
    "instagram",
    "twitter",
    "tiktok",
    "kabum",
    "kabun",
    "shopee",
    "amazon",
    "mercado livre",
    "mercadolivre",
    "gemini",
    "google ai studio",
    "googleaistudio",
    "grok",
    "chatgpt",
    "lovable",
    "v0",
    "perplexity",
    "googlestitch",
    "stitch",
    "linkedin",
]


# --- FUNÇÕES DE DADOS ---
def carregar_sites():
    """Carrega os sites do arquivo JSON."""
    try:
        with open(CONFIG_FILE, "r", encoding="utf-8") as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        salvar_sites(SITES_PALAVRAS_CHAVE_PADRAO)
        return SITES_PALAVRAS_CHAVE_PADRAO


def salvar_sites(sites):
    """Salva a lista de sites no arquivo JSON."""
    with open(CONFIG_FILE, "w", encoding="utf-8") as f:
        json.dump(sites, f, indent=4, ensure_ascii=False)


# --- FUNÇÕES DE MONITORAMENTO ---
def get_active_window_title():
    """Obtém o título da janela ativa usando wmctrl ou xdotool."""
    try:
        # Tenta primeiro com xdotool
        result = subprocess.run(
            ["xdotool", "getactivewindow", "getwindowname"],
            capture_output=True,
            text=True,
            timeout=1,
        )
        if result.returncode == 0:
            return result.stdout.strip().lower()
    except (FileNotFoundError, subprocess.TimeoutExpired):
        pass

    try:
        # Fallback para wmctrl
        result = subprocess.run(
            ["wmctrl", "-lx"], capture_output=True, text=True, timeout=1
        )
        if result.returncode == 0:
            lines = result.stdout.splitlines()
            for line in lines:
                if "  N/A" not in line:  # Linha da janela ativa geralmente
                    parts = line.split(None, 4)
                    if len(parts) >= 5:
                        return parts[4].lower()
    except (FileNotFoundError, subprocess.TimeoutExpired):
        pass

    return ""


def close_active_tab():
    """Fecha a aba ativa usando Ctrl+W."""
    try:
        # Envia Ctrl+W para fechar apenas a aba
        subprocess.run(["xdotool", "key", "ctrl+w"], timeout=2)
        return True
    except:
        return False


# --- CLASSE PRINCIPAL ---
class FocusMonitorApp(Gtk.Window):
    def __init__(self):
        super().__init__(title="Monitor de Foco - Linux")
        self.set_default_size(350, 450)
        self.set_border_width(10)
        self.set_position(Gtk.WindowPosition.CENTER)

        # Variáveis de controle
        self.monitoring_active = False
        self.monitor_thread = None
        self.sites_atuais = carregar_sites()

        # Configurar CSS para tema escuro
        self.setup_css()

        # Criar interface
        self.create_widgets()

        # Configurar indicador de sistema
        self.setup_app_indicator()

        # Conectar evento de fechar janela
        self.connect("delete-event", self.on_window_delete)

    def setup_css(self):
        """Aplica tema escuro personalizado."""
        css_provider = Gtk.CssProvider()
        css = b"""
        window {
            background-color: #1e1e1e;
        }
        
        textview, textview text {
            background-color: #2d2d2d;
            color: #e0e0e0;
            font-size: 14px;
        }
        
        label {
            color: #e0e0e0;
        }
        
        button {
            background-image: none;
            background-color: #4CAF50;
            color: white;
            border-radius: 6px;
            padding: 10px;
            font-weight: bold;
        }
        
        button:hover {
            background-color: #45a049;
        }
        
        .stop-button {
            background-color: #d32f2f;
        }
        
        .stop-button:hover {
            background-color: #b71c1c;
        }
        
        .status-active {
            color: #4CAF50;
            font-weight: bold;
        }
        
        .status-inactive {
            color: #757575;
        }
        
        .status-warning {
            color: #ff9800;
            font-weight: bold;
        }
        """
        css_provider.load_from_data(css)

        screen = Gdk.Screen.get_default()
        style_context = Gtk.StyleContext()
        style_context.add_provider_for_screen(
            screen, css_provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        )

    def create_widgets(self):
        """Cria todos os widgets da interface."""
        # Container principal
        vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        self.add(vbox)

        # Título
        title_label = Gtk.Label()
        title_label.set_markup(
            "<span size='large' weight='bold'>Palavras-chave a monitorar</span>"
        )
        vbox.pack_start(title_label, False, False, 5)

        # Área de texto com scroll
        scrolled = Gtk.ScrolledWindow()
        scrolled.set_vexpand(True)
        scrolled.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)

        self.textview = Gtk.TextView()
        self.textview.set_wrap_mode(Gtk.WrapMode.WORD)
        self.textbuffer = self.textview.get_buffer()
        self.textbuffer.set_text("\n".join(self.sites_atuais))

        scrolled.add(self.textview)
        vbox.pack_start(scrolled, True, True, 0)

        # Frame de botões de controle
        button_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        button_box.set_halign(Gtk.Align.CENTER)

        # Botão Importar
        btn_import = Gtk.Button(label="Importar JSON")
        btn_import.connect("clicked", self.on_import_clicked)
        btn_import.set_size_request(150, 40)
        button_box.pack_start(btn_import, False, False, 0)
        self.btn_import = btn_import

        # Botão Exportar
        btn_export = Gtk.Button(label="Exportar JSON")
        btn_export.connect("clicked", self.on_export_clicked)
        btn_export.set_size_request(150, 40)
        button_box.pack_start(btn_export, False, False, 0)
        self.btn_export = btn_export

        vbox.pack_start(button_box, False, False, 5)

        # Botão de toggle monitoramento
        self.btn_toggle = Gtk.Button(label="Iniciar Monitoramento")
        self.btn_toggle.connect("clicked", self.on_toggle_clicked)
        self.btn_toggle.set_size_request(300, 45)
        vbox.pack_start(self.btn_toggle, False, False, 5)

        # Label de status
        self.status_label = Gtk.Label(label="Status: Inativo")
        self.status_label.get_style_context().add_class("status-inactive")
        vbox.pack_start(self.status_label, False, False, 5)

        # Info sobre dependências
        info_label = Gtk.Label()
        info_label.set_markup(
            "<span size='small'><i>Requer: xdotool ou wmctrl instalado</i></span>"
        )
        vbox.pack_start(info_label, False, False, 0)

    def setup_app_indicator(self):
        """Configura o indicador na bandeja do sistema."""
        self.indicator = AppIndicator3.Indicator.new(
            "focus-monitor",
            "application-default-icon",
            AppIndicator3.IndicatorCategory.APPLICATION_STATUS,
        )
        self.indicator.set_status(AppIndicator3.IndicatorStatus.ACTIVE)
        self.indicator.set_title("Monitor de Foco")

        # Menu do indicador
        menu = Gtk.Menu()

        item_show = Gtk.MenuItem(label="Abrir Monitor")
        item_show.connect("activate", self.on_show_window)
        menu.append(item_show)

        item_quit = Gtk.MenuItem(label="Sair")
        item_quit.connect("activate", self.on_quit)
        menu.append(item_quit)

        menu.show_all()
        self.indicator.set_menu(menu)

    def get_keywords_from_textview(self):
        """Obtém as palavras-chave da área de texto."""
        start = self.textbuffer.get_start_iter()
        end = self.textbuffer.get_end_iter()
        text = self.textbuffer.get_text(start, end, False)
        return [k.lower().strip() for k in text.splitlines() if k.strip()]

    def on_toggle_clicked(self, button):
        """Inicia ou para o monitoramento."""
        if self.monitoring_active:
            # Parar monitoramento
            self.monitoring_active = False
            self.btn_toggle.set_label("Iniciar Monitoramento")
            self.btn_toggle.get_style_context().remove_class("stop-button")
            self.update_status("Status: Inativo", "status-inactive")
            self.textview.set_editable(True)
            self.btn_import.set_sensitive(True)
            self.btn_export.set_sensitive(True)
        else:
            # Iniciar monitoramento
            self.sites_atuais = self.get_keywords_from_textview()
            salvar_sites(self.sites_atuais)

            self.monitoring_active = True
            self.btn_toggle.set_label("Parar Monitoramento")
            self.btn_toggle.get_style_context().add_class("stop-button")
            self.update_status("Status: Ativo e vigiando...", "status-active")
            self.textview.set_editable(False)
            self.btn_import.set_sensitive(False)
            self.btn_export.set_sensitive(False)

            # Iniciar thread de monitoramento
            self.monitor_thread = threading.Thread(target=self.run_monitor, daemon=True)
            self.monitor_thread.start()

            # Esconder para a bandeja (opcional)
            self.hide()

    def run_monitor(self):
        """Executa o loop de monitoramento."""
        print("Monitoramento iniciado...")
        while self.monitoring_active:
            try:
                title = get_active_window_title()
                if title:
                    for keyword in self.sites_atuais:
                        if keyword in title:
                            GLib.idle_add(
                                self.update_status,
                                f"Distração detectada: '{keyword}'! Fechando...",
                                "status-warning",
                            )

                            close_active_tab()
                            time.sleep(1)

                            GLib.idle_add(
                                self.update_status,
                                "Status: Ativo e vigiando...",
                                "status-active",
                            )
                            break
            except Exception as e:
                print(f"Erro no monitor: {e}")

            time.sleep(1.5)

        print("Monitoramento finalizado.")

    def update_status(self, text, css_class):
        """Atualiza o label de status."""
        self.status_label.set_text(text)

        # Remove classes antigas
        context = self.status_label.get_style_context()
        for cls in ["status-active", "status-inactive", "status-warning"]:
            context.remove_class(cls)

        # Adiciona nova classe
        context.add_class(css_class)

    def on_import_clicked(self, button):
        """Importa configuração de arquivo JSON."""
        dialog = Gtk.FileChooserDialog(
            title="Importar Configuração",
            parent=self,
            action=Gtk.FileChooserAction.OPEN,
        )
        dialog.add_buttons(
            Gtk.STOCK_CANCEL,
            Gtk.ResponseType.CANCEL,
            Gtk.STOCK_OPEN,
            Gtk.ResponseType.OK,
        )

        filter_json = Gtk.FileFilter()
        filter_json.set_name("Arquivos JSON")
        filter_json.add_pattern("*.json")
        dialog.add_filter(filter_json)

        response = dialog.run()
        if response == Gtk.ResponseType.OK:
            filepath = dialog.get_filename()
            try:
                with open(filepath, "r", encoding="utf-8") as f:
                    sites_importados = json.load(f)
                    if isinstance(sites_importados, list):
                        self.textbuffer.set_text("\n".join(sites_importados))
                        salvar_sites(sites_importados)
            except Exception as e:
                print(f"Erro ao importar: {e}")

        dialog.destroy()

    def on_export_clicked(self, button):
        """Exporta configuração para arquivo JSON."""
        dialog = Gtk.FileChooserDialog(
            title="Exportar Configuração",
            parent=self,
            action=Gtk.FileChooserAction.SAVE,
        )
        dialog.add_buttons(
            Gtk.STOCK_CANCEL,
            Gtk.ResponseType.CANCEL,
            Gtk.STOCK_SAVE,
            Gtk.ResponseType.OK,
        )
        dialog.set_current_name("sites_config.json")

        response = dialog.run()
        if response == Gtk.ResponseType.OK:
            filepath = dialog.get_filename()
            sites_para_exportar = self.get_keywords_from_textview()
            try:
                with open(filepath, "w", encoding="utf-8") as f:
                    json.dump(sites_para_exportar, f, indent=4, ensure_ascii=False)
            except Exception as e:
                print(f"Erro ao exportar: {e}")

        dialog.destroy()

    def on_window_delete(self, widget, event):
        """Esconde a janela em vez de fechá-la."""
        self.hide()
        return True

    def on_show_window(self, item):
        """Mostra a janela novamente."""
        self.show_all()
        self.present()

    def on_quit(self, item):
        """Encerra o aplicativo."""
        self.monitoring_active = False
        Gtk.main_quit()


# --- PONTO DE ENTRADA ---
def main():
    app = FocusMonitorApp()
    app.show_all()
    Gtk.main()


if __name__ == "__main__":
    main()
