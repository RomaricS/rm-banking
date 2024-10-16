import { CardHiddenSymbols, ShortCardHiddenSymbols } from '@/constants';
import { formatAmount } from '@/lib/utils';
import Image from 'next/image';
import Link from 'next/link';
import React from 'react';

const bankCard = ({
    userName,
    account,
}: CreditCardProps) => {
    return (
        <div className='flex flex-col'>
            <Link
                className='bank-card'
                href='/'>
                <div className='bank-card_content'>
                    <div>
                        <h1 className="text-16 font-semibold text-white">
                            {account?.name ?? userName}
                        </h1>
                        <p className="font-ibm-plex-serif font-black text-white">
                            {formatAmount(account.currentBalance)}
                        </p>
                    </div>

                    <article className="flex flex-col gap-2">
                        <div className="flex justify-between">
                            <h1 className="text-12 font-semibold text-white">{userName}</h1>
                            <h2 className="text-12 font-semibold text-white">{ShortCardHiddenSymbols}</h2>
                        </div>
                        <p className="text-14 font-semibold tracking-[1.1px] text-white">
                        {CardHiddenSymbols} <span className="text-16">{account.mask}</span>
                        </p>
                    </article>
                </div>

                <div className="bank-card_icon">
                    <Image src='/icons/Paypass.svg' alt='Card image' width={20} height={24} />
                    <Image src='/icons/mastercard.svg' alt='Mastercard' className='ml-5' width={25} height={32} />
                </div>
                <Image src='/icons/lines.svg' alt='lines' className='absolute top-0 left-0' width={316} height={190} />
            </Link>
            {/* Copy card info */}
        </div>
    );
};

export default bankCard;
