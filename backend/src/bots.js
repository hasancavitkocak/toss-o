// Test kullanıcılarının (bot) otomatik cevapları: uygulama tek başına
// denenirken de mektup gelip gitsin diye.

const FRIEND_REPLIES = [
  'çok teşekkür ederim !!\nbu benim için çok anlamlı,\nkelimelerle anlatamam.\nbugün mektubunu almak\nyüzüme kocaman bir gülümseme kondurdu.\nher zaman yanımda olduğun için\nteşekkür ederim.',
  'uçağın tam pencereme kondu !!\nokurken kahvem soğudu,\nhiç umurumda olmadı.\nseni çok özledim,\nen kısa zamanda buluşalım mı?',
  'mektubunu üç kere okudum.\ninsanın böyle bir arkadaşı olması\nbüyük şans.\nbu akşam seni düşüneceğim,\nkendine çok iyi bak.',
];

const STRANGER_REPLIES = [
  'merhaba yabancı !!\nmektubun gökyüzünden\ntam balkonuma düştü.\nbu koca dünyada birinin\nbana yazması çok güzel.\nburadan sana kocaman\nbir gülümseme yolluyorum.',
  'kim olduğunu bilmiyorum\nama günümü güzelleştirdin.\nburada hava çok güzel,\nkeşke sen de görebilsen.\numarım uçağım sana da ulaşır.',
  'kağıt uçağın rüzgârla geldi,\nşehrin üstünde tur attı\nve tam önüme indi.\nbu bir işaret olmalı.\nselamlar, uzaklardan sevgiyle.',
];

const FRIEND_REPLIES_EN = [
  "thank you so much !!\nthis means a lot to me,\nmore than words can say.\nyour letter put\na huge smile on my face today.\nthanks for always being there.",
  "your plane landed right on my windowsill !!\nmy coffee went cold while reading,\ni didn't mind at all.\ni miss you so much,\nshall we meet soon?",
  "i read your letter three times.\nhaving a friend like you\nis a real stroke of luck.\ni'll think of you tonight,\ntake good care of yourself.",
];

const STRANGER_REPLIES_EN = [
  "hello stranger !!\nyour letter fell from the sky\nright onto my balcony.\nin this big world, someone\nwriting to me feels lovely.\nsending you a big smile from here.",
  "i don't know who you are\nbut you made my day.\nthe weather here is beautiful,\ni wish you could see it.\ni hope my plane reaches you too.",
  "your paper plane came with the wind,\ncircled over the city\nand landed right in front of me.\nthis must be a sign.\ngreetings, with love from afar.",
];

/** Bot cevabı; gönderenin dilinde (tr / en) */
export function botReplyText(bot, isFriend, lang = 'tr') {
  const en = lang === 'en';
  const pool = isFriend
    ? (en ? FRIEND_REPLIES_EN : FRIEND_REPLIES)
    : (en ? STRANGER_REPLIES_EN : STRANGER_REPLIES);
  const body = pool[Math.floor(Math.random() * pool.length)];
  const name = bot.display_name.toLocaleLowerCase(en ? 'en' : 'tr-TR');
  return `${body}\n${en ? 'love' : 'sevgiyle'},\n${name}.`;
}

/** Bot, arkadaşlık isteğini birkaç saniye sonra kabul eder */
export function scheduleBotAccept({ accept, delayMs, log }) {
  const [min, max] = delayMs;
  const wait = (min + Math.random() * (max - min)) / 2;
  return new Promise((resolve) => {
    const t = setTimeout(async () => {
      try {
        await accept();
      } catch (err) {
        log?.error({ err }, 'bot isteği kabul edemedi');
      }
      resolve();
    }, wait);
    t.unref?.();
  });
}

/** Bota gelen mektuba birkaç saniye sonra cevap uçağı gönder */
export function scheduleBotReply({ pool, letter, bot, sender, delayMs, log }) {
  if (sender.is_bot) return null;
  const [min, max] = delayMs;
  const wait = min + Math.random() * (max - min);
  return new Promise((resolve) => {
    const t = setTimeout(async () => {
      try {
        const { rows } = await pool.query(
          'select 1 from friendships where user_id = $1 and friend_id = $2',
          [bot.id, sender.id],
        );
        await pool.query(
          `insert into letters (sender_id, recipient_id, body, reply_to, distance_km)
           values ($1, $2, $3, $4, $5)`,
          [bot.id, sender.id, botReplyText(bot, rows.length > 0, sender.lang), letter.id, letter.distance_km],
        );
      } catch (err) {
        log?.error({ err }, 'bot cevabı gönderilemedi');
      }
      resolve();
    }, wait);
    t.unref?.();
  });
}
