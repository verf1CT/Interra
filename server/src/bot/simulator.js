// Интерактивный терминальный симулятор чат-бота «Интерра»
// Позволяет протестировать все 28 шагов без подключения к Telegram.

import readline from 'node:readline';
import { BotEngine } from './botEngine.js';

const engine = new BotEngine();
const userId = 'sim-user-1';

const rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout
});

function displayStep(step) {
  console.log('\n======================================================');
  console.log(`[${step.stepId}] ${step.category || ''} -> ${step.screenName || ''}`);
  console.log('------------------------------------------------------');
  console.log(step.text);

  if (step.buttons && step.buttons.length > 0) {
    console.log('\nДоступные кнопки:');
    step.buttons.forEach((b, idx) => {
      const urlText = b.url ? ` (Ссылка: ${b.url})` : '';
      console.log(`  [${idx + 1}] ${b.text}${urlText}`);
    });
  }
  console.log('======================================================\n');
}

async function run() {
  console.log('Запуск симулятора чат-бота «Интерра»...');
  let currentStep = await engine.handleStart(userId);
  displayStep(currentStep);

  promptUser(currentStep);
}

function promptUser(currentStep) {
  rl.question('Введите номер кнопки или текст сообщения (или "exit" для выхода): ', async (answer) => {
    const input = answer.trim();

    if (input.toLowerCase() === 'exit') {
      console.log('Выход из симулятора.');
      rl.close();
      return;
    }

    const num = parseInt(input, 10);
    if (!isNaN(num) && currentStep.buttons && num >= 1 && num <= currentStep.buttons.length) {
      const chosenButton = currentStep.buttons[num - 1];
      console.log(`\nВы нажали кнопку: "${chosenButton.text}"`);

      if (chosenButton.url) {
        console.log(`Переход по внешней ссылке: ${chosenButton.url}`);
      }

      if (chosenButton.next) {
        currentStep = await engine.handleButtonClick(userId, chosenButton.next, chosenButton.value);
        displayStep(currentStep);

        // Если автопереход (например, сброс порта)
        if (currentStep.isAutoTransition && currentStep.next) {
          console.log('Ожидание завершения операции сброса (симуляция 1.5 сек)...');
          await new Promise(r => setTimeout(r, 1500));
          currentStep = await engine.transitionTo(engine.getSession(userId), currentStep.next);
          displayStep(currentStep);
        }
      }
    } else {
      console.log(`\nВы отправили текст: "${input}"`);
      currentStep = await engine.handleTextInput(userId, input);
      displayStep(currentStep);

      if (currentStep.isAutoTransition && currentStep.next) {
        console.log('Ожидание операции...');
        await new Promise(r => setTimeout(r, 1500));
        currentStep = await engine.transitionTo(engine.getSession(userId), currentStep.next);
        displayStep(currentStep);
      }
    }

    promptUser(currentStep);
  });
}

if (process.argv[1] && process.argv[1].endsWith('simulator.js')) {
  run();
}
