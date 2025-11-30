#!/bin/bash
# Script de automação para criar, compilar e empacotar o Monitor de Foco (C++ Qt)

APP_NAME="focusmonitor"
VERSION="1.0"
ARCH=$(dpkg --print-architecture)
MAINTAINER="Seu Nome <seu.email@exemplo.com>"
BUILD_DIR="./build"
PACKAGE_DIR="${APP_NAME}-${VERSION}-${ARCH}"
ICON_FILE="icone.png" # Nome do arquivo de ícone

# Diretório raiz onde o script está sendo executado
ROOT_DIR=$(pwd)

# --- 1. CONFIGURAÇÃO DO AMBIENTE ---
echo "--- 1. Configurando ambiente e dependências ---"

# Verifica se o qmake6 está disponível
if ! command -v qmake6 &> /dev/null
then
    echo "ERRO: O qmake6 não foi encontrado. Instale o Qt 6 dev tools (e.g., sudo apt install qt6-base-dev qt6-tools-dev-tools build-essential)."
    exit 1
fi

# Verifica se os utilitários de sistema necessários estão instalados
REQUIRED_TOOLS=("xdotool" "wmctrl")
for tool in "${REQUIRED_TOOLS[@]}"; do
    if ! command -v "$tool" &> /dev/null
    then
        echo "AVISO: Utilitário '$tool' não está instalado. Necessário para a funcionalidade principal."
    fi
done

# Cria e entra no diretório de build
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR" || { echo "Falha ao entrar no diretório de build."; exit 1; }

# --- 2. GERAÇÃO DOS ARQUIVOS DE CÓDIGO (DENTRO DE ./build) ---
echo "--- 2. Gerando arquivos de código em $BUILD_DIR ---"

# Limpa o diretório de build antes de criar novos arquivos
rm -f focusmonitor.pro focusmonitorapp.h focusmonitorapp.cpp main.cpp

# Arquivo de Projeto Qt
cat << EOF > focusmonitor.pro
QT += widgets
QT += core

SOURCES += \\
    main.cpp \\
    focusmonitorapp.cpp

HEADERS += \\
    focusmonitorapp.h

CONFIG += c++17
EOF

# Arquivo focusmonitorapp.h
cat << 'EOF' > focusmonitorapp.h
#ifndef FOCUSMONITORAPP_H
#define FOCUSMONITORAPP_H

#include <QtWidgets>
#include <QThread>
#include <QList>
#include <QSystemTrayIcon>
#include <QMenu>
#include <atomic>

// Thread de monitoramento que interage com o sistema (xdotool/wmctrl)
class MonitorThread : public QThread {
    Q_OBJECT
public:
    // Passamos nullptr para o construtor para evitar problemas de destruição de objeto Qt (Segmentation Fault)
    explicit MonitorThread(QObject *parent = nullptr); 
    void run() override;
    void stopMonitoring();
    void updateKeywords(const QList<QString>& keywords);

signals:
    // Sinaliza distração de volta para a GUI
    void distractionDetected(const QString &keyword); 
    // Sinaliza mudança de status
    void statusUpdated(const QString &message, const QString &style); 

private:
    std::atomic<bool> m_running;
    QList<QString> m_keywords;
    
    QString getActiveWindowTitle();
    bool closeActiveTab();
};

// Classe principal da janela
class FocusMonitorApp : public QMainWindow {
    Q_OBJECT

public:
    FocusMonitorApp(QWidget *parent = nullptr);
    ~FocusMonitorApp();

private slots:
    void onToggleClicked();
    void handleDistraction(const QString &keyword);
    void updateStatusLabel(const QString &text, const QString &cssClass);
    void onImportClicked();
    void onExportClicked();
    void onTrayIconActivated(QSystemTrayIcon::ActivationReason reason);
    void showWindow();
    void quitApplication();

protected:
    void closeEvent(QCloseEvent *event) override;

private:
    // Widgets
    QPushButton *m_toggleButton;
    QTextEdit *m_keywordsTextEdit;
    QLabel *m_statusLabel;
    
    MonitorThread *m_monitorThread;
    
    // System Tray
    QSystemTrayIcon *m_trayIcon;
    QMenu *m_trayMenu;
    
    // Funções auxiliares
    QList<QString> getKeywordsFromTextEdit();
    void loadKeywords();
    void saveKeywords(const QList<QString>& keywords);
    void setupUi();
    void setupStyles();
    void setupSystemTray();
};

#endif // FOCUSMONITORAPP_H
EOF

# Arquivo focusmonitorapp.cpp
cat << 'EOF' > focusmonitorapp.cpp
#include "focusmonitorapp.h"
#include <QFile>
#include <QJsonDocument>
#include <QJsonArray>
#include <QJsonObject>
#include <QProcess>
#include <QMessageBox>
#include <QFileDialog>
#include <QStyle>
#include <QRegularExpression>

// --- Configurações ---
const QString CONFIG_FILE = "sites_config.json";
const QList<QString> DEFAULT_KEYWORDS = {
    "youtube", "facebook", "instagram", "twitter", "tiktok", 
    "kabum", "shopee", "amazon", "mercado livre", "gemini", 
    "chatgpt", "perplexity", "linkedin"
};

// --- Implementação da Thread de Monitoramento ---

MonitorThread::MonitorThread(QObject *parent) : QThread(parent), m_running(false) {}

void MonitorThread::updateKeywords(const QList<QString>& keywords) {
    m_keywords = keywords;
}

void MonitorThread::stopMonitoring() {
    m_running = false;
}

QString MonitorThread::getActiveWindowTitle() {
    QProcess process;
    // 1. Tenta xdotool
    process.start("xdotool", QStringList() << "getactivewindow" << "getwindowname");
    if (process.waitForFinished(1000) && process.exitCode() == 0) {
        return process.readAllStandardOutput().trimmed().toLower();
    }
    
    // 2. Fallback para wmctrl (obter todas as janelas e tentar identificar a ativa)
    process.start("wmctrl", QStringList() << "-lx");
    if (process.waitForFinished(1000) && process.exitCode() == 0) {
        QStringList lines = QString(process.readAllStandardOutput()).split('\n', Qt::SkipEmptyParts);
        
        if (!lines.isEmpty()) {
            // O wmctrl -lx lista a janela ativa geralmente em uma linha
            // Vamos tentar a abordagem mais simples de parsing
            for (const QString& line : lines) {
                // Heurística simples: se a linha não contiver "N/A" (desktop), 
                // assumimos que é uma janela de alto nível.
                // Isso não é 100% preciso, mas simula o fallback.
                if (!line.contains(" N/A")) {
                    QStringList parts = line.split(QRegularExpression("\\s+"), Qt::SkipEmptyParts);
                    if (parts.size() >= 5) {
                        return parts.mid(4).join(' ').toLower();
                    }
                }
            }
        }
    }
    
    return "";
}

bool MonitorThread::closeActiveTab() {
    // Comando xdotool para enviar Ctrl+W
    QProcess::startDetached("xdotool", QStringList() << "key" << "ctrl+w");
    return true;
}

void MonitorThread::run() {
    m_running = true;
    emit statusUpdated("Status: Ativo e vigiando...", "status-active");
    
    while (m_running) {
        QString title = getActiveWindowTitle();
        if (!title.isEmpty()) {
            for (const QString& keyword : m_keywords) {
                if (title.contains(keyword)) {
                    emit distractionDetected(keyword);
                    closeActiveTab();
                    QThread::sleep(2); // Pausa após fechar
                    break; 
                }
            }
        }
        QThread::msleep(1500); // Espera 1.5 segundos entre checagens
    }
    
    emit statusUpdated("Status: Inativo", "status-inactive");
}

// --- Implementação da Aplicação Principal (GUI) ---

FocusMonitorApp::FocusMonitorApp(QWidget *parent)
    // CORREÇÃO DE SEGMENTATION FAULT: MonitorThread inicializada sem 'this' como pai.
    : QMainWindow(parent), m_monitorThread(new MonitorThread(nullptr)), m_trayIcon(nullptr), m_trayMenu(nullptr) { 
    
    setWindowTitle("Monitor de Foco - C++ Qt Linux");
    resize(400, 500);
    
    setupUi();
    loadKeywords(); // Carrega após a criação do TextEdit
    setupStyles();
    setupSystemTray();
    
    // Conexões de Slots e Sinais
    connect(m_toggleButton, &QPushButton::clicked, this, &FocusMonitorApp::onToggleClicked);
    connect(m_monitorThread, &MonitorThread::distractionDetected, this, &FocusMonitorApp::handleDistraction);
    connect(m_monitorThread, &MonitorThread::statusUpdated, this, &FocusMonitorApp::updateStatusLabel);
}

FocusMonitorApp::~FocusMonitorApp() {
    if (m_monitorThread->isRunning()) {
        m_monitorThread->stopMonitoring();
        m_monitorThread->wait();
    }
    // Delete explícito é necessário pois passamos nullptr no construtor.
    delete m_monitorThread;
    
    // Cleanup do system tray
    if (m_trayIcon) {
        delete m_trayIcon;
    }
    if (m_trayMenu) {
        delete m_trayMenu;
    }
}

void FocusMonitorApp::setupStyles() {
    // Estilos CSS para replicar o tema escuro do Python/GTK
    QString styleSheet = R"(
        QMainWindow { background-color: #1e1e1e; }
        QLabel { color: #e0e0e0; font-size: 14px; }
        QTextEdit { 
            background-color: #2d2d2d; 
            color: #e0e0e0; 
            font-size: 14px; 
            border: 1px solid #454545;
        }
        QPushButton {
            background-color: #4CAF50;
            color: white;
            border-radius: 6px;
            padding: 10px;
            font-weight: bold;
            min-height: 30px;
        }
        QPushButton:hover { background-color: #45a049; }
        .stop-button { background-color: #d32f2f; }
        .stop-button:hover { background-color: #b71c1c; }
    )";
    
    this->setStyleSheet(styleSheet);
    
    // Aplica classes customizadas via QObject::setProperty
    // O statusLabel precisa de um estilo dinâmico que será aplicado via updateStatusLabel
    m_statusLabel->setProperty("cssClass", "status-inactive");
    m_statusLabel->style()->polish(m_statusLabel); 
    
    // Define estilos para as classes de status
    QString statusStyles = R"(
        QLabel[cssClass="status-active"] { color: #4CAF50; font-weight: bold; }
        QLabel[cssClass="status-inactive"] { color: #757575; font-weight: bold; }
        QLabel[cssClass="status-warning"] { color: #ff9800; font-weight: bold; }
    )";
    qApp->setStyleSheet(qApp->styleSheet() + statusStyles);
}

void FocusMonitorApp::setupUi() {
    QWidget *centralWidget = new QWidget(this);
    setCentralWidget(centralWidget);

    QVBoxLayout *vbox = new QVBoxLayout(centralWidget);
    vbox->setSpacing(10);
    
    // Título
    QLabel *titleLabel = new QLabel("Palavras-chave a monitorar");
    titleLabel->setAlignment(Qt::AlignCenter);
    titleLabel->setStyleSheet("font-size: 18px; font-weight: bold;");
    vbox->addWidget(titleLabel);

    // Área de texto
    m_keywordsTextEdit = new QTextEdit;
    m_keywordsTextEdit->setPlaceholderText("Digite uma palavra-chave por linha...");
    vbox->addWidget(m_keywordsTextEdit);
    
    // Botões Importar/Exportar
    QHBoxLayout *buttonBox = new QHBoxLayout;
    QPushButton *btnImport = new QPushButton("Importar JSON");
    QPushButton *btnExport = new QPushButton("Exportar JSON");
    
    connect(btnImport, &QPushButton::clicked, this, &FocusMonitorApp::onImportClicked);
    connect(btnExport, &QPushButton::clicked, this, &FocusMonitorApp::onExportClicked);
    
    buttonBox->addWidget(btnImport);
    buttonBox->addWidget(btnExport);
    vbox->addLayout(buttonBox);

    // Botão de Toggle
    m_toggleButton = new QPushButton("Iniciar Monitoramento");
    vbox->addWidget(m_toggleButton);
    
    // Label de Status
    m_statusLabel = new QLabel("Status: Inativo");
    m_statusLabel->setAlignment(Qt::AlignCenter);
    vbox->addWidget(m_statusLabel);
    
    // Info dependências
    QLabel *infoLabel = new QLabel("<i>Requer: xdotool ou wmctrl instalado</i>");
    infoLabel->setAlignment(Qt::AlignCenter);
    infoLabel->setStyleSheet("font-size: 10px; color: #a0a0a0;");
    vbox->addWidget(infoLabel);
}

void FocusMonitorApp::setupSystemTray() {
    // Tenta carregar o ícone de diferentes locais
    QIcon icon;
    
    // 1. Tenta carregar do diretório atual (para desenvolvimento)
    if (QFile::exists("icone.png")) {
        icon = QIcon("icone.png");
    }
    // 2. Tenta carregar do diretório de instalação
    else if (QFile::exists("/usr/share/icons/hicolor/64x64/apps/focusmonitor.png")) {
        icon = QIcon("/usr/share/icons/hicolor/64x64/apps/focusmonitor.png");
    }
    // 3. Tenta usar o ícone do tema do sistema
    else {
        icon = QIcon::fromTheme("focusmonitor");
    }
    
    // Se nenhum ícone foi encontrado, usa um ícone padrão do sistema
    if (icon.isNull()) {
        icon = QIcon::fromTheme("application-x-executable");
    }
    
    // Cria o menu do system tray
    m_trayMenu = new QMenu(this);
    
    QAction *showAction = m_trayMenu->addAction("Mostrar Janela");
    connect(showAction, &QAction::triggered, this, &FocusMonitorApp::showWindow);
    
    m_trayMenu->addSeparator();
    
    QAction *quitAction = m_trayMenu->addAction("Sair");
    connect(quitAction, &QAction::triggered, this, &FocusMonitorApp::quitApplication);
    
    // Cria o ícone da bandeja
    m_trayIcon = new QSystemTrayIcon(icon, this);
    m_trayIcon->setContextMenu(m_trayMenu);
    m_trayIcon->setToolTip("Monitor de Foco");
    
    // Conecta o clique no ícone
    connect(m_trayIcon, &QSystemTrayIcon::activated, this, &FocusMonitorApp::onTrayIconActivated);
    
    // Mostra o ícone
    m_trayIcon->show();
}

// --- Funções de Dados ---

QList<QString> FocusMonitorApp::getKeywordsFromTextEdit() {
    QString text = m_keywordsTextEdit->toPlainText();
    QStringList lines = text.split('\n', Qt::SkipEmptyParts);
    QList<QString> keywords;
    for (const QString& line : lines) {
        keywords.append(line.trimmed().toLower());
    }
    return keywords;
}

void FocusMonitorApp::loadKeywords() {
    QFile file(CONFIG_FILE);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        saveKeywords(DEFAULT_KEYWORDS); // Salva o padrão se não encontrar
        m_keywordsTextEdit->setText(DEFAULT_KEYWORDS.join('\n'));
        return; 
    }
    
    QByteArray jsonData = file.readAll();
    QJsonDocument doc = QJsonDocument::fromJson(jsonData);
    
    if (doc.isArray()) {
        QJsonArray array = doc.array();
        QList<QString> sites;
        for (const QJsonValue &value : array) {
            if (value.isString()) {
                sites.append(value.toString());
            }
        }
        m_keywordsTextEdit->setText(sites.join('\n'));
    } else {
        QMessageBox::warning(this, "Aviso", "Arquivo de configuração inválido. Usando palavras-chave padrão.");
        m_keywordsTextEdit->setText(DEFAULT_KEYWORDS.join('\n'));
        saveKeywords(DEFAULT_KEYWORDS);
    }
}

void FocusMonitorApp::saveKeywords(const QList<QString>& keywords) {
    QFile file(CONFIG_FILE);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Text)) {
        QMessageBox::warning(this, "Erro de Salvamento", "Não foi possível salvar a configuração.");
        return;
    }
    
    QJsonArray array;
    for (const QString& keyword : keywords) {
        array.append(keyword);
    }
    
    QJsonDocument doc(array);
    file.write(doc.toJson(QJsonDocument::JsonFormat::Indented));
}

// --- Slots de Interface e Controle ---

void FocusMonitorApp::onToggleClicked() {
    if (m_monitorThread->isRunning()) {
        // Parar monitoramento
        m_monitorThread->stopMonitoring();
        m_monitorThread->wait();
        
        m_toggleButton->setText("Iniciar Monitoramento");
        m_toggleButton->setProperty("cssClass", "");
        m_toggleButton->style()->polish(m_toggleButton);
        m_keywordsTextEdit->setReadOnly(false);
    } else {
        // Iniciar monitoramento
        QList<QString> keywords = getKeywordsFromTextEdit();
        if (keywords.isEmpty()) {
            QMessageBox::warning(this, "Aviso", "A lista de palavras-chave está vazia. Adicione termos para iniciar.");
            return;
        }

        saveKeywords(keywords);
        m_monitorThread->updateKeywords(keywords);
        
        m_monitorThread->start();
        
        m_toggleButton->setText("Parar Monitoramento");
        m_toggleButton->setProperty("cssClass", "stop-button");
        m_toggleButton->style()->polish(m_toggleButton);
        m_keywordsTextEdit->setReadOnly(true);
        
        // Esconder para a bandeja (simula o comportamento do AppIndicator GTK)
        hide();
    }
}

void FocusMonitorApp::handleDistraction(const QString &keyword) {
    // Este Slot é chamado na thread principal (GUI)
    updateStatusLabel(
        QString("Distração detectada: '%1'! Fechando...").arg(keyword), 
        "status-warning"
    );
}

void FocusMonitorApp::updateStatusLabel(const QString &text, const QString &cssClass) {
    // Remove classes antigas e adiciona a nova
    m_statusLabel->setText(text);
    m_statusLabel->setProperty("cssClass", cssClass);
    // Força a atualização do estilo com a nova propriedade
    m_statusLabel->style()->polish(m_statusLabel); 
}

void FocusMonitorApp::onImportClicked() {
    QString filePath = QFileDialog::getOpenFileName(this, "Importar Configuração", "", "Arquivos JSON (*.json)");
    if (filePath.isEmpty()) return;

    QFile file(filePath);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        QMessageBox::critical(this, "Erro", "Não foi possível abrir o arquivo para importação.");
        return;
    }
    
    QByteArray jsonData = file.readAll();
    QJsonDocument doc = QJsonDocument::fromJson(jsonData);
    
    if (doc.isArray()) {
        QJsonArray array = doc.array();
        QList<QString> sites;
        for (const QJsonValue &value : array) {
            if (value.isString()) {
                sites.append(value.toString());
            }
        }
        m_keywordsTextEdit->setText(sites.join('\n'));
        saveKeywords(sites); // Salva também no arquivo padrão
        QMessageBox::information(this, "Sucesso", "Configuração importada com sucesso.");
    } else {
        QMessageBox::critical(this, "Erro", "Arquivo JSON inválido. Deve ser uma lista de strings.");
    }
}

void FocusMonitorApp::onExportClicked() {
    QString filePath = QFileDialog::getSaveFileName(this, "Exportar Configuração", "sites_config.json", "Arquivos JSON (*.json)");
    if (filePath.isEmpty()) return;

    QFile file(filePath);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Text)) {
        QMessageBox::critical(this, "Erro", "Não foi possível criar o arquivo para exportação.");
        return;
    }
    
    QList<QString> sites = getKeywordsFromTextEdit();
    QJsonArray array;
    for (const QString& keyword : sites) {
        array.append(keyword);
    }
    
    QJsonDocument doc(array);
    file.write(doc.toJson(QJsonDocument::JsonFormat::Indented));
    QMessageBox::information(this, "Sucesso", "Configuração exportada com sucesso.");
}

void FocusMonitorApp::closeEvent(QCloseEvent *event) {
    // Esconde a janela em vez de fechar, para manter o monitoramento em background
    hide();
    
    // Mostra uma notificação informando que o app continua rodando
    if (m_trayIcon && m_trayIcon->isVisible()) {
        m_trayIcon->showMessage(
            "Monitor de Foco",
            "O aplicativo continua rodando em segundo plano.",
            QSystemTrayIcon::Information,
            2000
        );
    }
    
    event->ignore();
}

void FocusMonitorApp::onTrayIconActivated(QSystemTrayIcon::ActivationReason reason) {
    if (reason == QSystemTrayIcon::Trigger || reason == QSystemTrayIcon::DoubleClick) {
        showWindow();
    }
}

void FocusMonitorApp::showWindow() {
    show();
    raise();
    activateWindow();
}

void FocusMonitorApp::quitApplication() {
    // Para o monitoramento antes de sair
    if (m_monitorThread->isRunning()) {
        m_monitorThread->stopMonitoring();
        m_monitorThread->wait();
    }
    
    QApplication::quit();
}
EOF

# Arquivo main.cpp
cat << 'EOF' > main.cpp
#include <QApplication>
#include "focusmonitorapp.h"

int main(int argc, char *argv[]) {
    QApplication a(argc, argv);
    
    // Desativa a saída quando a última janela é fechada, permitindo que a aplicação rode em background (como um AppIndicator)
    a.setQuitOnLastWindowClosed(false); 
    
    FocusMonitorApp w;
    w.show();
    
    return a.exec();
}
EOF

echo "Arquivos de código criados com sucesso!"
ls -la

# --- 3. COMPILAÇÃO DO PROJETO (DENTRO DE ./build) ---
echo "--- 3. Compilando o executável $APP_NAME ---"
qmake6 focusmonitor.pro
if [ $? -ne 0 ]; then
    echo "ERRO: Falha no qmake6. Verifique o arquivo focusmonitor.pro."
    exit 1
fi

make
if [ $? -ne 0 ]; then
    echo "ERRO: Falha na compilação C++. Verifique os arquivos no diretório build."
    exit 1
fi

# Move o executável para o diretório raiz
cp "$APP_NAME" "$ROOT_DIR/"

# Volta para o diretório raiz
cd "$ROOT_DIR"

# --- 4. PREPARAÇÃO DA ESTRUTURA DO DEB ---
echo "--- 4. Preparando a estrutura do pacote DEB com ícone ---"

# Limpa estruturas antigas
rm -rf "$PACKAGE_DIR"
rm -f "${PACKAGE_DIR}.deb"

# Cria a estrutura base do pacote
mkdir -p "$PACKAGE_DIR/DEBIAN"
mkdir -p "$PACKAGE_DIR/usr/bin"
mkdir -p "$PACKAGE_DIR/usr/share/applications"

# 4.1. Adiciona o diretório para ícones (tamanho 64x64, comum para painéis/menus)
ICON_SIZE="64x64"
ICON_DIR="$PACKAGE_DIR/usr/share/icons/hicolor/$ICON_SIZE/apps"
mkdir -p "$ICON_DIR"

# 4.2. Cópia do Ícone e Binário
# O ícone é esperado estar no mesmo diretório que o script.
if [ -f "$ICON_FILE" ]; then
    echo "Incluindo ícone: $ICON_FILE"
    # Copia o ícone para o diretório de hicolor
    cp "$ICON_FILE" "$ICON_DIR/${APP_NAME}.png"
else
    echo "AVISO: Arquivo de ícone '$ICON_FILE' não encontrado no diretório do script. O ícone do aplicativo será padrão."
fi

cp "$APP_NAME" "$PACKAGE_DIR/usr/bin/"

# 4.3. Cria o arquivo de controle (DEBIAN/control)
cat << EOF > "$PACKAGE_DIR/DEBIAN/control"
Package: ${APP_NAME}
Version: ${VERSION}
Section: utils
Priority: optional
Architecture: ${ARCH}
Maintainer: ${MAINTAINER}
Depends: libqt6widgets6, libqt6core6, xdotool, wmctrl, libqt6gui6, libqt6network6
Description: Monitor de Foco para Linux (Qt C++).
 Este programa monitora o titulo da janela ativa e fecha abas distrativas.
EOF

# 4.4. Cria o arquivo Desktop
cat << EOF > "$PACKAGE_DIR/usr/share/applications/${APP_NAME}.desktop"
[Desktop Entry]
Version=1.0
Type=Application
Name=Dopamina - Foco
Comment=Fecha abas do navegador que contêm palavras-chave distrativas.
Exec=/usr/bin/${APP_NAME}
Icon=${APP_NAME}
Terminal=false
Categories=Utility;Productivity;
StartupWMClass=${APP_NAME}
EOF

# --- 5. CONSTRUÇÃO DO PACOTE DEB ---
echo "--- 5. Construindo o pacote ${PACKAGE_DIR}.deb ---"

# Usa sudo para garantir as permissões corretas no arquivo DEBIAN
sudo dpkg-deb --build "$PACKAGE_DIR"
if [ $? -ne 0 ]; then
    echo "ERRO: Falha ao construir o pacote DEB. Verifique as permissões ou o arquivo control."
    exit 1
fi

echo "--- SUCESSO ---"
echo "Executável gerado: ./${APP_NAME}"
echo "Pacote .deb gerado: ./${PACKAGE_DIR}.deb"
echo "O ícone '$ICON_FILE' foi incluído."
echo "Instalação:"
echo "sudo dpkg -i ./${PACKAGE_DIR}.deb"
echo "-------------------"
